import SwiftUI

struct ArtworkSelection: Identifiable {
    let asset: String
    let title: String
    var id: String { asset }
}

struct CharacterDetailView: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var proactive: ProactiveChatCoordinator
    let character: CompanionCharacter
    let invite: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var artwork: ArtworkSelection?
    @State private var detailTab = 0
    @State private var preview = 0
    @State private var showingAlarm = false
    @State private var showingMotion = false
    @State private var showingAI = false
    @State private var showingStickers = false
    @State private var showingButtons = false
    @State private var showingIsland = false
    @State private var showingProactive = false
    private var selected: CharacterArtwork { store.worldArtwork(for: character) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    artworkPicker
                    tabs
                    if detailTab == 1 { dailySummary }
                    if detailTab == 2 { settingsSummary }
                    featureGrid
                    feature("主动聊天", subtitle: "设置她的联系时段、最短间隔与私聊／群聊", symbol: "bubble.left.and.exclamationmark.bubble.right", identifier: "characterProactiveChatSettings") { showingProactive = true }
                    islandAndAlarm
                    Button(action: invite) {
                        Label(store.session == nil ? "邀请\(character.name)上岛" : "查看当前陪伴", systemImage: "sparkles")
                    }.buttonStyle(MoonPrimaryButton()).accessibilityIdentifier("inviteCharacter")
                    if store.session != nil {
                        Text("本轮角色保持不变，结束陪伴后可切换。").font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6))
                    }
                }.padding(.horizontal, 18).padding(.bottom, 28)
            }.scrollIndicators(.hidden)
        }
        .background { MoonBackdrop().ignoresSafeArea() }
        .foregroundStyle(MoonPalette.ink).tint(MoonPalette.violet)
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.large]).presentationDragIndicator(.hidden)
        .fullScreenCover(item: $artwork) { item in ArtworkViewer(item: item) }
        .sheet(isPresented: $showingAlarm) {
            NavigationStack { CharacterAlarmEditor(alarms: store.alarms, character: character) }
        }
        .sheet(isPresented: $showingStickers) {
            NavigationStack { CharacterStickerLibraryView(store: chatStore, character: character) }
        }
        .sheet(isPresented: $showingAI) {
            NavigationStack { AIChatSettingsView(store: chatStore, character: character) }
        }
        .sheet(isPresented: $showingProactive) {
            NavigationStack { ProactiveChatSettingsView(store: chatStore, coordinator: proactive, character: character) }
        }
        .sheet(isPresented: $showingButtons) { buttonStyleSheet }
        .sheet(isPresented: $showingIsland) { islandSheet }
        .sheet(isPresented: $showingMotion) {
            NavigationStack {
                MotionSettingsView(store: store, character: character)
                    .navigationTitle("日常动作").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showingMotion = false }.accessibilityIdentifier("closeMotionSettings")
                    } }
            }.tint(MoonPalette.violet)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-tasks") { showingMotion = true }
            if ProcessInfo.processInfo.arguments.contains("--preview-gallery-chibi") { showChibi() }
            if ProcessInfo.processInfo.arguments.contains("--preview-gallery-standing") { showStanding() }
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill").font(.system(size: 28)).foregroundStyle(MoonPalette.gold)
            VStack(alignment: .leading, spacing: 3) {
                Text("角色档案").font(.system(size: 21, weight: .semibold, design: .serif))
                Text("CHARACTER DOSSIER").font(.system(size: 8, weight: .medium)).tracking(2.5)
                    .foregroundStyle(MoonPalette.violet.opacity(0.6))
            }
            Spacer(minLength: 4)
            Menu {
                Button("查看岛上小人物大图") { showChibi() }.accessibilityIdentifier("artwork-chibi")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 19)).frame(width: 36, height: 44)
            }.accessibilityLabel("更多角色操作").accessibilityIdentifier("characterDossierMore")
            MoonIconButton(symbol: "xmark", label: "关闭角色档案") { dismiss() }
                .accessibilityIdentifier("closeCharacterDetail")
        }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
    }

    private var hero: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                MoonBackdrop()
                Circle().fill(.white.opacity(0.55)).overlay(Circle().stroke(MoonPalette.gold.opacity(0.35), lineWidth: 1))
                    .frame(width: width * 0.88, height: width * 0.88).offset(x: width * 0.21, y: 30)
                Button { showStanding() } label: {
                    Image(selected.asset).resizable().scaledToFit()
                        .frame(width: width * 0.86, height: geometry.size.height - 14)
                }.buttonStyle(.plain).position(x: width * 0.61, y: geometry.size.height * 0.53)
                    .accessibilityLabel("查看\(selected.title)大图").accessibilityIdentifier("artwork-standing")
                VStack(alignment: .leading, spacing: 11) {
                    Text(character.name).font(.system(size: typeSize.isAccessibilitySize ? 27 : 32, weight: .semibold, design: .serif))
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(character.subtitle).font(.system(size: 12)).foregroundStyle(MoonPalette.ink.opacity(0.65))
                    HStack(spacing: 5) {
                        Rectangle().fill(MoonPalette.gold).frame(height: 1)
                        Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(MoonPalette.gold)
                    }.frame(width: 64).padding(.vertical, 8)
                    Text("“").font(.system(size: 29, design: .serif)).foregroundStyle(MoonPalette.lavender)
                    Text(character.introduction).font(.system(size: 13, weight: .medium, design: .serif)).lineSpacing(5)
                }.frame(width: width * 0.37, alignment: .leading).padding(.leading, 14).padding(.top, 26)
                    .shadow(color: MoonPalette.paper, radius: 4)
                if character.availableArtworks.count > 1 {
                    HStack {
                        MoonIconButton(symbol: "chevron.left", label: "上一张展示图") { stepArtwork(-1) }
                            .accessibilityIdentifier("previousCharacterArtwork")
                        Spacer()
                        MoonIconButton(symbol: "chevron.right", label: "下一张展示图") { stepArtwork(1) }
                            .accessibilityIdentifier("nextCharacterArtwork")
                    }.padding(.horizontal, 10).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 32)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(MoonPalette.gold.opacity(0.3), lineWidth: 1))
        }.frame(height: typeSize.isAccessibilitySize ? 480 : 450).accessibilityIdentifier("characterDossierHero")
    }

    private var artworkPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(character.availableArtworks) { item in
                    let active = selected.id == item.id
                    Button { store.selectWorldArtwork(item.id, for: character) } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .topTrailing) {
                                MoonPalette.lavender.opacity(0.23)
                                Image(item.asset).resizable().scaledToFill()
                                    .frame(width: 148, height: 78, alignment: .top).clipped()
                                if active { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, MoonPalette.violet).padding(5) }
                            }.frame(width: 148, height: 78).clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? MoonPalette.violet : MoonPalette.gold.opacity(0.25), lineWidth: active ? 2 : 1))
                            Text(item.title).font(.system(size: 12, weight: active ? .semibold : .regular, design: .serif)).lineLimit(1).frame(width: 148)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("在我的世界展示\(item.title)")
                        .accessibilityIdentifier("worldArtwork_\(item.id)").accessibilityAddTraits(active ? .isSelected : [])
                }
            }.padding(2)
        }.accessibilityIdentifier("worldArtworkPicker")
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Array(["展示", "日常", "设定"].enumerated()), id: \.offset) { index, title in
                Button { detailTab = index } label: {
                    Text(title).font(.system(size: 16, weight: .medium, design: .serif))
                        .frame(maxWidth: .infinity, minHeight: 42).foregroundStyle(detailTab == index ? .white : MoonPalette.ink)
                        .background(detailTab == index ? MoonPalette.violet : .clear, in: Capsule())
                        .overlay(Capsule().stroke(detailTab == index ? MoonPalette.gold : .clear, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityAddTraits(detailTab == index ? .isSelected : [])
            }
        }.padding(4).background(.white.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(MoonPalette.gold.opacity(0.4), lineWidth: 1))
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 270 : 145), spacing: 10)], spacing: 10) {
            feature("日常动作", subtitle: (character.motionProfile?.dailyActions ?? []).map(\.title).joined(separator: " · "), symbol: "figure.play", identifier: "characterMotionSettings") { showingMotion = true }
            feature("AI 与人格", subtitle: "模型、人设与聊天权限", symbol: "bubble.left.and.text.bubble.right", identifier: "characterAISettings") { showingAI = true }
            feature("专属表情", subtitle: "内置与自定义表情包", symbol: "face.smiling", identifier: "characterStickerLibrary") { showingStickers = true }
            feature("按钮风格", subtitle: "定制主页互动按钮", symbol: "paintbrush.pointed.fill", identifier: "characterHomeButtonStyles") { showingButtons = true }
        }
    }

    private func feature(_ title: String, subtitle: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(MoonPalette.violet)
                    .frame(width: 38, height: 42).background(MoonPalette.lavender.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 15, weight: .semibold, design: .serif))
                    Text(subtitle).font(.system(size: 9)).foregroundStyle(MoonPalette.ink.opacity(0.55)).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(MoonPalette.violet)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(MoonPalette.gold.opacity(0.25), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    private var islandAndAlarm: some View {
        VStack(spacing: 10) {
            Button { showingIsland = true } label: {
                HStack(spacing: 12) {
                    IslandArtPreview(character: character, expanded: false, scene: store.islandScene).scaleEffect(0.65).frame(width: 140, height: 38)
                    Text("灵动岛预览").font(.system(size: 14, weight: .medium, design: .serif))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption)
                }.padding(12).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 19))
                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(MoonPalette.gold.opacity(0.25), lineWidth: 1))
            }.buttonStyle(.plain).accessibilityIdentifier("characterIslandPreview")
            feature("角色闹钟", subtitle: "设置时间约定与到点提醒", symbol: "alarm", identifier: "characterAlarmSettings") { showingAlarm = true }
        }
    }
    private var dailySummary: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("属于\(character.name)的日常").font(.system(size: 18, weight: .semibold, design: .serif))
                Text("自动活动、走路、打滚与专属动作，均为角色独立保存。").font(.subheadline).foregroundStyle(MoonPalette.ink.opacity(0.6))
                Button("选择她的日常动作 →") { showingMotion = true }.font(.subheadline.weight(.medium))
            }
        }
    }
    private var settingsSummary: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(character.name)的设定").font(.system(size: 18, weight: .semibold, design: .serif))
                Text("主页按钮：\(store.homeButtonStyle(for: character).title)").font(.subheadline)
                HStack { Text("外观").font(.subheadline); Spacer(); AppearanceToggle() }
            }
        }
    }
    private var buttonStyleSheet: some View {
        NavigationStack {
            ScrollView { CharacterHomeButtonStylePicker(store: store, character: character).padding(18) }
                .background(MoonPalette.paper).navigationTitle("主页按钮风格").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingButtons = false } } }
        }.tint(MoonPalette.violet)
    }
    private var islandSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("预览形态", selection: $preview) { Text("日常").tag(0); Text("展开").tag(1); Text("锁屏").tag(2) }.pickerStyle(.segmented)
                    if preview == 2 { lockScreenPreview }
                    else { IslandArtPreview(character: character, expanded: preview == 1, scene: store.islandScene) }
                    Text("尺寸效果示意，实际展示由系统安排。").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(MoonPalette.paper).navigationTitle("灵动岛预览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingIsland = false } } }
        }.tint(MoonPalette.violet)
    }
    private var lockScreenPreview: some View {
        HStack(spacing: 12) {
            CharacterStanding(character: character, width: 62, height: 88)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(character.name).foregroundStyle(DragonPalette.lavender); Spacer(); Text("24:59").monospacedDigit() }
                    .font(.system(size: 12, weight: .semibold))
                Text(character.introduction).font(.system(size: 12)).lineLimit(2)
                Text("招呼     心情     结束").font(.system(size: 10)).foregroundStyle(DragonPalette.lavender)
            }
        }.padding(14).foregroundStyle(DragonPalette.softWhite)
            .background(DragonPalette.ink, in: RoundedRectangle(cornerRadius: 23)).accessibilityLabel("锁屏实时活动示意")
    }
    private func showStanding() { artwork = ArtworkSelection(asset: selected.asset, title: "\(character.name) · \(selected.id == "default" ? "展开立绘" : selected.title)") }
    private func showChibi() { artwork = ArtworkSelection(asset: character.chibiAsset + "Detail", title: "\(character.name) · 岛上小人物") }
    private func stepArtwork(_ direction: Int) {
        let items = character.availableArtworks
        let index = items.firstIndex(where: { $0.id == selected.id }) ?? 0
        store.selectWorldArtwork(items[(index + direction + items.count) % items.count].id, for: character)
    }
}
