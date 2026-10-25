import SwiftUI

struct ArtworkSelection: Identifiable {
    let asset: String
    let title: String
    var id: String { asset }
}

struct CharacterDetailView: View {
    @ObservedObject var store: CompanionStore
    let character: CompanionCharacter
    let invite: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var artwork: ArtworkSelection?
    @State private var preview = 0

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
                    IslandArtPreview(character: character, expanded: preview == 1)
                        .frame(maxWidth: .infinity)
                }
                Text("这是尺寸效果示意，实际显示由系统安排。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
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
        .task {
            #if DEBUG
            try? await Task.sleep(nanoseconds: 700_000_000)
            if ProcessInfo.processInfo.arguments.contains("--preview-gallery-chibi") { showChibi() }
            if ProcessInfo.processInfo.arguments.contains("--preview-gallery-standing") { showStanding() }
            #endif
        }
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
