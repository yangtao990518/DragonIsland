import SwiftUI
import UIKit

private enum WorldTab: Hashable {
    case world, characters, chat, alarms, about

    static var initial: WorldTab {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-characters") { return .characters }
        if ProcessInfo.processInfo.arguments.contains("--preview-chat") { return .chat }
        if ProcessInfo.processInfo.arguments.contains("--preview-about") { return .about }
        if ProcessInfo.processInfo.arguments.contains("--preview-alarms") { return .alarms }
        #endif
        return .world
    }
}

struct ContentView: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var alarms: CharacterAlarmStore
    @StateObject private var chatStore: ChatStore
    @StateObject private var chatTools: ChatAppTools
    @StateObject private var proactive: ProactiveChatCoordinator
    @State private var tab = WorldTab.initial
    @State private var minutes = 25
    @State private var expandedPreview = false
    @State private var detailCharacter: CompanionCharacter?
    @State private var legacyHomePanel: HomeShortcutKind?
    private let homeScenes = HomeSceneAnimation.load()
    @AppStorage("characterBrowsingMode") private var characterBrowsingMode = "cards"
    @State private var browsedCharacterID = "xiaobai"
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(store: CompanionStore) {
        self.store = store
        self.alarms = store.alarms
        let provider: any ChatReplyProvider
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--chat-media-tools-tests") {
            provider = ChatMediaTestProvider()
        } else if ProcessInfo.processInfo.arguments.contains("--maiverse-capture") {
            provider = TestChatReplyProvider()
        } else { provider = DeepSeekChatReplyProvider(secrets: AIChatCredentials()) }
        #else
        provider = DeepSeekChatReplyProvider(secrets: AIChatCredentials())
        #endif
        let chat = ChatStore(characters: store.characters, provider: provider)
        #if DEBUG
        ChatMediaTestSupport.seed(chat)
        ChatScrollTestSupport.seed(chat)
        #endif
        let tools = ChatAppTools(companion: store)
        tools.permission = { [weak chat] id in
            guard let chat, let character = chat.character(id) else { return false }
            return chat.configuration.profile(for: character).appControl == true
        }
        chat.appToolHandler = { [weak tools] id, call, args in
            guard let tools else { throw CancellationError() }
            return try await tools.execute(characterID: id, call: call, args: args)
        }
        _chatStore = StateObject(wrappedValue: chat)
        _chatTools = StateObject(wrappedValue: tools)
        _proactive = StateObject(wrappedValue: ProactiveChatCoordinator(store: chat))
    }

    var body: some View {
        TabView(selection: $tab) {
            worldPage
                .tabItem { Label("我的世界", systemImage: "sparkles") }.tag(WorldTab.world)
            charactersPage
                .tabItem { Label("角色", systemImage: "person.2") }.tag(WorldTab.characters)
            ChatPage(store: chatStore, tools: chatTools, proactive: proactive)
                .tabItem { Label("聊天", systemImage: "bubble.left.and.bubble.right") }.tag(WorldTab.chat)
                .badge(chatStore.conversations.reduce(0) { $0 + $1.unreadProactiveCount })
            CharacterAlarmsPage(alarms: store.alarms, characters: store.characters)
                .tabItem { Label("闹钟", systemImage: "alarm") }.tag(WorldTab.alarms)
            aboutPage
                .tabItem { Label("关于", systemImage: "circle.grid.2x2") }.tag(WorldTab.about)
        }
        .tint(AppPalette.accent)
        .onChange(of: chatStore.requestedConversationID) { _, id in if id != nil { tab = .chat } }
        .onChange(of: chatStore.conversations.reduce(0) { $0 + $1.unreadProactiveCount }) { _, _ in
            Task { await proactive.refresh(prepare: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name(ChatDeepLink.notificationName))) { _ in
            tab = .chat
            Task { await proactive.refresh(prepare: false) }
        }
        .onChange(of: chatStore.history.proactive) { _, _ in
            Task { await proactive.refresh(prepare: false) }
        }
        .onOpenURL { url in
            if let id = ChatDeepLink.conversationID(url) {
                tab = .chat
                UserDefaults.standard.set(id.uuidString, forKey: ChatDeepLink.pendingKey)
                Task { await proactive.refresh(prepare: false) }
            }
        }
        .task(id: (scenePhase == .active ? 1 : 0) + (chatStore.history.proactive?.settings.enabled == true ? 2 : 0)) {
            guard scenePhase == .active else { return }
            await proactive.refresh()
            guard chatStore.proactiveState.settings.enabled else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard chatStore.proactiveState.settings.enabled else { return }
                await proactive.refresh()
            }
        }
        .onAppear {
            browsedCharacterID = store.selectedCharacterID
            if UserDefaults.standard.string(forKey: ChatDeepLink.pendingKey) != nil { tab = .chat }
        }
        .toolbarBackground(AppPalette.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $detailCharacter) { character in
            NavigationStack {
                CharacterDetailView(store: store, chatStore: chatStore, character: character) {
                    store.select(character)
                    detailCharacter = nil
                    tab = .world
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $legacyHomePanel) { kind in
            HomeShortcutPanel(store: store, character: store.displayCharacter, kind: kind)
        }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--character-dafeiyu"), let character = store.characters.first(where: { $0.id == "dafeiyu" }) {
                store.select(character)
            }
            if args.contains("--preview-tasks") { detailCharacter = store.selectedCharacter }
            for scene in IslandScene.allCases where args.contains("--scene-\(scene.rawValue)") {
                await store.setIslandScene(scene)
            }
            if args.contains("--preview-detail") || args.contains("--preview-gallery-chibi") || args.contains("--preview-gallery-standing") {
                detailCharacter = store.selectedCharacter
            }
            if args.contains("--preview-live-motion") { await store.setMotionSettings(MotionSettings()); await store.start(minutes: 25) }
            if args.contains("--preview-island-dances") {
                await store.setMotionSettings(MotionSettings(walk: false, roll: false, ride: false,
                    petWalk: false, dance1: true, dance2: true))
                await store.start(minutes: 25)
            }
            #endif
        }
        .alert("mAIverse", isPresented: Binding(
            get: { store.notice != nil }, set: { if !$0 { store.notice = nil } }
        )) {
            Button("知道了", role: .cancel) { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }

    @ViewBuilder private var worldPage: some View {
        if let scene = homeScenes.first(where: { $0.characterID == store.displayCharacter.id }) {
            DafeiyuHomePage(store: store, chat: chatStore, clip: scene, visible: tab == .world, controls: {
                if let session = store.session { activeSession(session) }
                else { setupSession }
            }, openCharacters: { tab = .characters }, openDetails: { detailCharacter = store.displayCharacter })
        } else { legacyWorldPage }
    }

    private var legacyWorldPage: some View {
        WorldPage {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("mAIverse").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("你的世界，他们也在。")
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.48))
                }
                Spacer()
                AppearanceToggle()
                Button { tab = .characters } label: {
                    CharacterAvatar(character: store.displayCharacter, size: 32)
                        .padding(7)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .overlay(Circle().stroke(AppPalette.accent.opacity(0.35), lineWidth: 1))
                }
                .accessibilityLabel("查看角色")
            }
            Button { detailCharacter = store.displayCharacter } label: {
                CharacterHero(character: store.displayCharacter, active: store.session != nil,
                              artworkAsset: store.worldArtwork(for: store.displayCharacter).asset)
            }.buttonStyle(.plain).accessibilityLabel("查看\(store.displayCharacter.name)角色详情")
                .accessibilityIdentifier("worldCharacterCard")
                .accessibilityValue(store.worldArtwork(for: store.displayCharacter).id)
                .overlay(alignment: .topTrailing) {
                    HomeGameShortcutRail(style: store.homeButtonStyle(for: store.displayCharacter),
                        character: store.displayCharacter, open: { legacyHomePanel = $0 }, size: 64)
                        .padding(.trailing, 8).padding(.top, 18)
                }
            if let session = store.session {
                activeSession(session)
            } else {
                setupSession
            }
            islandPreview
            HStack(spacing: 6) {
                Image(systemName: "heart")
                Text("把一小段日常，留给喜欢的角色。")
            }
            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.35))
            .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
    }

    private var setupSession: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("这次，陪你多久？").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("1 分钟体验").font(.system(size: 10)).foregroundStyle(AppPalette.status)
            }
            HStack(spacing: 8) {
                ForEach([1, 25, 50, 120], id: \.self) { value in
                    Button { minutes = value } label: {
                        VStack(spacing: 3) {
                            Text("\(value)").font(.system(size: 23, weight: .semibold, design: .rounded))
                            Text("分钟").font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(minutes == value ? AppPalette.background : Color.primary)
                        .background(minutes == value ? AppPalette.accent : Color.primary.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("陪伴 \(value) 分钟")
                    .accessibilityAddTraits(minutes == value ? .isSelected : [])
                }
            }
            CompanionVoiceSettings(alarms: store.alarms, character: store.selectedCharacter)
            Button { Task { await store.start(minutes: minutes) } } label: {
                HStack(spacing: 8) {
                    if store.busy { ProgressView().tint(AppPalette.background) }
                    Image(systemName: "sparkles")
                    Text("让\(store.selectedCharacter.name)陪着我").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14))
                .padding(.horizontal, 17).frame(height: 48)
                .foregroundStyle(AppPalette.background)
                .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain).disabled(store.busy || alarms.busy).accessibilityIdentifier("startCompanion")
        }
        .worldCard()
    }

    private func activeSession(_ session: CompanionSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let expired = session.hasExpired(at: timeline.date)
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(expired ? "这轮陪伴已完成" : "\(store.displayCharacter.name)正在陪你",
                              systemImage: expired ? "checkmark.circle" : session.mood.symbol)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(AppPalette.status)
                        Text(expired ? "辛苦啦，休息一下吧。" : session.mood.title)
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                    Spacer(minLength: 8)
                    DragonCountdown(state: session, expired: expired)
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .frame(width: 108, alignment: .trailing)
                }
                Text(expired ? "下一段时间，也可以一起度过。" : session.message)
                    .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !expired {
                    HStack(spacing: 9) {
                        CompanionAction(title: "打个招呼", symbol: "hand.wave.fill", disabled: store.busy) {
                            await store.greet()
                        }
                        CompanionAction(title: "换个心情", symbol: "sparkles", disabled: store.busy) {
                            await store.changeMood()
                        }
                    }
                }
                Button { Task { await store.finish() } } label: {
                    Text(expired ? "收起这一轮，准备再出发" : "结束本轮陪伴")
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .disabled(store.busy)
            }
            .worldCard()
        }
    }

    private var islandPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("在岛上，遇见你").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("界面示意").font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Picker("预览形态", selection: $expandedPreview) {
                Text("日常 · 小人物").tag(false)
                Text("展开 · 立绘").tag(true)
            }.pickerStyle(.segmented)
            IslandArtPreview(character: store.displayCharacter, expanded: expandedPreview, scene: store.islandScene)
                .frame(maxWidth: .infinity)
            Text("开始陪伴后回到桌面，长按灵动岛展开。")
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
        }
        .worldCard()
    }

    private var charactersPage: some View {
        WorldPage {
            HStack {
                if characterBrowsingMode == "cards" {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("角色").font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("左右滑动，认识你的岛上伙伴。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    PageHeading(eyebrow: "RESIDENTS", title: "住进你的世界", subtitle: "小小的身影，也有完整的模样。")
                }
                Spacer(minLength: 4)
                AppearanceToggle()
            }
            Picker("角色浏览方式", selection: $characterBrowsingMode) {
                Text("横向卡片").tag("cards")
                Text("纵向列表").tag("list")
            }.pickerStyle(.segmented).accessibilityIdentifier("characterBrowsingMode")
            if characterBrowsingMode == "cards" {
                TabView(selection: $browsedCharacterID) {
                    ForEach(store.characters) { character in
                        residentCard(character).padding(.horizontal, 2).tag(character.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 470)
                .accessibilityIdentifier("characterCardPager")
                .overlay(alignment: .top) {
                    HStack {
                        characterPageArrow(offset: -1)
                        Spacer()
                        characterPageArrow(offset: 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 112)
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(store.characters) { character in
                                Button {
                                    withAnimation { browsedCharacterID = character.id }
                                } label: {
                                    VStack(spacing: 7) {
                                        CharacterAvatar(character: character, size: 48)
                                            .padding(5)
                                            .overlay(Circle().stroke(browsedCharacterID == character.id ? AppPalette.accent : .clear, lineWidth: 2))
                                        Text(character.name).font(.caption)
                                    }.foregroundStyle(browsedCharacterID == character.id ? AppPalette.accent : .secondary)
                                }.buttonStyle(.plain).id(character.id)
                                    .accessibilityIdentifier("quickCharacter-\(character.id)")
                                    .accessibilityLabel("查看\(character.name)卡片")
                                    .accessibilityAddTraits(browsedCharacterID == character.id ? .isSelected : [])
                            }
                        }.padding(4)
                    }
                    .onChange(of: browsedCharacterID) { _, id in
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                Text("左右滑动、点两侧箭头或头像切换角色；点卡片设置她的日常动作。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.characters) { character in residentCard(character) }
            }
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(AppPalette.accent)
                Text("这里会慢慢热闹起来。")
                    .font(.system(size: 16, weight: .medium))
                Text("更多角色，等待与你相遇。")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            if store.session != nil {
                Text("结束本轮陪伴后，可以切换住民。")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
            }
        }
    }

    private func characterPageArrow(offset: Int) -> some View {
        let current = store.characters.firstIndex(where: { $0.id == browsedCharacterID }) ?? 0
        let next = current + offset
        let available = store.characters.indices.contains(next)
        return Button {
            guard available else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                browsedCharacterID = store.characters[next].id
            }
        } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(AppPalette.accent.opacity(0.12), lineWidth: 1))
                .opacity(available ? 1 : 0.28)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityIdentifier(offset < 0 ? "previousCharacterCard" : "nextCharacterCard")
        .accessibilityLabel(available
            ? "\(offset < 0 ? "上" : "下")一个角色：\(store.characters[next].name)"
            : offset < 0 ? "已是第一个角色" : "已是最后一个角色")
    }

    private func residentCard(_ character: CompanionCharacter) -> some View {
        CharacterResidentCard(character: character,
                              selected: store.selectedCharacter.id == character.id,
                              active: store.session != nil,
                              artworkHeight: characterBrowsingMode == "cards" ? 210 : 302,
                              open: { detailCharacter = character }) { store.select(character) }
    }

    private var aboutPage: some View {
        WorldPage {
            HStack {
                PageHeading(eyebrow: "ABOUT YOUR WORLD", title: "mAIverse", subtitle: "My + AI + Universe · 我的 AI 小世界")
                Spacer(minLength: 4)
                AppearanceToggle()
            }
            IslandScenePicker(store: store)
            AppIconPicker()
            VStack(alignment: .leading, spacing: 17) {
                Text("你的世界，他们也在。")
                    .font(.system(size: 21, weight: .semibold))
                Text("让喜欢的角色住进手机，陪你专注，也陪你放松。小白是这里的第一位住民。")
                    .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.65)).lineSpacing(5)
                Divider().overlay(Color.primary.opacity(0.08))
                Label("陪伴与聊天记录保存在本机，AI 聊天支持单聊与群组。", systemImage: "iphone")
                Label("聊天记录保存在本机，删除 App 会同时删除本机记录。", systemImage: "bubble.left.and.bubble.right")
                Label("AI 聊天需配置自己的 DeepSeek 密钥；密钥保存在本机钥匙串。", systemImage: "lock")
                Label("可选择角色语音，到点由系统提醒；陪伴卡片仍可手动结束。", systemImage: "alarm")
            }
            .font(.system(size: 12)).foregroundStyle(Color.primary)
            .worldCard()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                HStack {
                    Label("实时活动与系统设置", systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14)).foregroundStyle(AppPalette.accent)
            }.worldCard()
            VStack(spacing: 7) {
                Text("mAIverse V\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.8")")
                Text("角色为非官方同人形象，与相关 AI 服务提供方无隶属关系。")
            }
            .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.35))
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }

}

