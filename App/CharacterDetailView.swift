import SwiftUI

struct ArtworkSelection: Identifiable {
    let asset: String
    let title: String
    var id: String { asset }
}

struct CharacterDetailView: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var chatStore: ChatStore
    let character: CompanionCharacter
    let invite: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var artwork: ArtworkSelection?
    @State private var preview = 0
    @State private var showingAlarm = false
    @State private var showingMotion = false
    @State private var showingAI = false
    @State private var showingStickers = false

    private func showChibi() {
        artwork = ArtworkSelection(asset: character.chibiAsset + "Detail", title: "\(character.name) · 岛上小人物")
    }
    private func showStanding() {
        artwork = ArtworkSelection(asset: character.heroAsset, title: "\(character.name) · 展开立绘")
    }

    var body: some View {
        WorldPage {
            PageHeading(eyebrow: "CHARACTER", title: character.name, subtitle: "\(character.subtitle) · \(character.origin)")
            Text(character.introduction).font(.system(size: 17, weight: .medium))
            worldArtworkPicker
            Button { showingMotion = true } label: {
                HStack {
                    Label("日常动作", systemImage: "figure.play")
                    Spacer()
                    Text((character.motionProfile?.dailyActions ?? []).map(\.title).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption)
                }.foregroundStyle(AppPalette.accent)
            }.worldCard().accessibilityIdentifier("characterMotionSettings")
            Button { showingAI = true } label: {
                HStack {
                    Label("AI 与人格", systemImage: "bubble.left.and.text.bubble.right")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }.foregroundStyle(AppPalette.accent)
            }.worldCard().accessibilityIdentifier("characterAISettings")
            Button { showingStickers = true } label: {
                HStack {
                    Label("专属表情包", systemImage: "face.smiling")
                    Spacer()
                    Text("静态 / GIF").font(.caption)
                    Image(systemName: "chevron.right").font(.caption)
                }.foregroundStyle(AppPalette.accent)
            }.worldCard().accessibilityIdentifier("characterStickerLibrary")
            HStack(alignment: .top, spacing: 12) {
                artworkTile(title: "展开立绘", subtitle: "展开 / 锁屏", asset: character.heroAsset, action: showStanding)
                    .accessibilityIdentifier("artwork-standing")
                artworkTile(title: "岛上小人物", subtitle: "日常 / 最小态", asset: character.chibiAsset + "Detail", action: showChibi)
                    .accessibilityIdentifier("artwork-chibi")
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("岛上效果预览").font(.system(size: 16, weight: .semibold))
                Picker("预览形态", selection: $preview) {
                    Text("日常").tag(0)
                    Text("展开").tag(1)
                    Text("锁屏").tag(2)
                }.pickerStyle(.segmented)
                if preview == 2 { lockScreenPreview }
                else {
                    IslandArtPreview(character: character, expanded: preview == 1, scene: store.islandScene)
                        .frame(maxWidth: .infinity)
                }
                Text("这是尺寸效果示意，实际显示由系统安排。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.worldCard()
            VStack(alignment: .leading, spacing: 15) {
                Label("\(character.name)的时间约定", systemImage: "alarm").font(.headline)
                CompanionVoiceSettings(alarms: store.alarms, character: character)
                Button("设置角色闹钟") { showingAlarm = true }
                    .buttonStyle(.borderedProminent).tint(AppPalette.accent)
                    .accessibilityIdentifier("characterAlarmSettings")
            }.worldCard()
            Button(action: invite) {
                Text(store.session == nil ? "邀请\(character.name)上岛" : "查看当前陪伴")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .foregroundStyle(AppPalette.onAccent)
                    .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
            if store.session != nil {
                Text("本轮角色保持不变，结束陪伴后可切换。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("角色详情").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("完成") { dismiss() }.accessibilityIdentifier("closeCharacterDetail")
            }
            ToolbarItem(placement: .topBarTrailing) { AppearanceToggle() }
        }
        .toolbarBackground(AppPalette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .fullScreenCover(item: $artwork) { item in ArtworkViewer(item: item) }
        .sheet(isPresented: $showingAlarm) {
            NavigationStack { CharacterAlarmEditor(alarms: store.alarms, character: character) }
        }
        .sheet(isPresented: $showingStickers) { NavigationStack { CharacterStickerLibraryView(store: chatStore, character: character) } }
        .sheet(isPresented: $showingAI) {
            NavigationStack { AIChatSettingsView(store: chatStore, character: character) }
        }
        .sheet(isPresented: $showingMotion) {
            NavigationStack {
                MotionSettingsView(store: store, character: character)
                    .navigationTitle("\(character.name)的日常动作").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { showingMotion = false }.accessibilityIdentifier("closeMotionSettings") }
                    }
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-tasks") { showingMotion = true }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if ProcessInfo.processInfo.arguments.contains("--preview-gallery-chibi") { showChibi() }
            if ProcessInfo.processInfo.arguments.contains("--preview-gallery-standing") { showStanding() }
            #endif
        }
    }

    private var worldArtworkPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我的世界展示照片").font(.headline)
            Text("选择这位角色在主页显示的照片，每个角色会单独记住。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(character.availableArtworks) { item in
                        let selected = store.worldArtwork(for: character).id == item.id
                        VStack(spacing: 8) {
                            Button { store.selectWorldArtwork(item.id, for: character) } label: {
                                VStack(spacing: 8) {
                                    Image(item.asset).resizable().scaledToFit()
                                        .frame(width: 136, height: 164)
                                        .background(AppPalette.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                    Label(item.title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                        .lineLimit(2).frame(height: 32)
                                }.padding(8)
                                    .foregroundStyle(selected ? AppPalette.accent : Color.primary)
                                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? AppPalette.accent : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("worldArtwork_\(item.id)")
                                .accessibilityLabel("在我的世界展示\(item.title)")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            Button("查看大图") { artwork = ArtworkSelection(asset: item.asset, title: "\(character.name) · \(item.title)") }
                                .font(.caption).foregroundStyle(AppPalette.accent)
                        }
                    }
                }.padding(2)
            }
        }.worldCard().accessibilityIdentifier("worldArtworkPicker")
    }

    private func artworkTile(title: String, subtitle: String, asset: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(asset).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .background(AppPalette.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11))
                }
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                Text("点开查看大图").font(.system(size: 10)).foregroundStyle(AppPalette.accent)
            }.frame(maxWidth: .infinity).worldCard()
        }.buttonStyle(.plain)
    }

    private var lockScreenPreview: some View {
        HStack(spacing: 12) {
            CharacterStanding(character: character, width: 62, height: 88)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(character.name).foregroundStyle(DragonPalette.lavender)
                    Spacer(minLength: 4)
                    Text("24:59").monospacedDigit()
                }.font(.system(size: 12, weight: .semibold))
                Text(character.introduction).font(.system(size: 12)).lineLimit(2)
                Text("招呼     心情     结束").font(.system(size: 10)).foregroundStyle(DragonPalette.lavender)
            }
        }
        .padding(14).foregroundStyle(DragonPalette.softWhite)
        .background(DragonPalette.ink, in: RoundedRectangle(cornerRadius: 23))
        .accessibilityLabel("锁屏实时活动示意")
    }
}
