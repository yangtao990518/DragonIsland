import SwiftUI

/// Scene pixels stay untouched. All labels, controls and dialogue are native overlays.
struct DafeiyuHomePage<Controls: View>: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var chat: ChatStore
    let clip: HomeSceneAnimation
    let visible: Bool
    let controls: Controls
    let openCharacters: () -> Void
    let openDetails: () -> Void
    @State private var replay = 0
    @State private var greeting: String?
    @State private var greetingError = false
    @State private var requesting = false
    @State private var greetingTask: Task<Void, Never>?
    @State private var panel: Panel?
    @Environment(\.scenePhase) private var scenePhase

    enum Panel: String, Identifiable { case actions, scene, island; var id: String { rawValue } }

    init(store: CompanionStore, chat: ChatStore, clip: HomeSceneAnimation, visible: Bool,
         @ViewBuilder controls: () -> Controls, openCharacters: @escaping () -> Void, openDetails: @escaping () -> Void) {
        self.store = store; self.chat = chat; self.clip = clip; self.visible = visible
        self.controls = controls(); self.openCharacters = openCharacters; self.openDetails = openDetails
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(red: 0.91, green: 0.94, blue: 0.98).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 14)
                        stage(width: max(1, geometry.size.width - 36))
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(.white.opacity(0.65), lineWidth: 1))
                            .shadow(color: Color(red: 0.15, green: 0.24, blue: 0.40).opacity(0.08), radius: 16, y: 7)
                            .padding(.horizontal, 18)
                        controls
                            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 22)
                    }
                }.scrollIndicators(.hidden)
            }
        }
        .accessibilityIdentifier("dafeiyuAnimatedHome")
        .sheet(item: $panel) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .actions: MotionSettingsView(store: store, character: store.displayCharacter)
                    case .scene: WorldPage { IslandScenePicker(store: store) }
                    case .island:
                        WorldPage {
                            PageHeading(eyebrow: "LIVE ACTIVITY", title: "灵动岛预览", subtitle: "开始陪伴后回到桌面，长按灵动岛展开。")
                            IslandArtPreview(character: store.displayCharacter, expanded: false, scene: store.islandScene)
                            IslandArtPreview(character: store.displayCharacter, expanded: true, scene: store.islandScene)
                        }
                    }
                }
                .navigationTitle(destination == .actions ? "日常动作" : destination == .scene ? "灵动岛场景" : "灵动岛预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { panel = nil }.accessibilityIdentifier("closeHomePanel") } }
            }
        }
        .onDisappear { cancelGreeting() }
        .onChange(of: visible) { _, value in if !value { cancelGreeting() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelGreeting() } }
    }

    private func stage(width: CGFloat) -> some View {
        HomeScenePlayer(clip: clip, visible: visible && panel == nil, replay: replay)
            .frame(width: width, height: width * CGFloat(clip.frameSize[1]) / CGFloat(clip.frameSize[0]))
            .overlay {
                // Keep tap area below the header; controls above take priority.
                Button { greet() } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).padding(.top, 60)
                    .accessibilityLabel("轻点大肥鱼，看看她想说什么")
                    .accessibilityIdentifier("worldCharacterGreeting")
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("大肥鱼").font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("活泼可爱的\n鲸鱼女仆").font(.system(size: 10)).lineSpacing(3)
                    if requesting || greeting != nil || greetingError {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(requesting ? "让我想想…" : greetingError ? "暂时没连上AI" : greeting ?? "")
                                .font(.system(size: 13, weight: .medium)).lineLimit(3)
                                .accessibilityIdentifier("homeCharacterDialogue")
                            if greetingError {
                                Button("去检查AI设置", action: openDetails).font(.caption2)
                            }
                        }
                        .padding(10).frame(width: 120, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 12)
                    }
                }
                .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.25))
                .padding(.leading, 16).padding(.top, 22)
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    shortcut("动作", symbol: "figure.walk", panel: .actions)
                    shortcutDivider
                    shortcut("场景", symbol: "photo", panel: .scene)
                    shortcutDivider
                    shortcut("预览", symbol: "capsule", panel: .island)
                }
                .padding(.horizontal, 4).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
                .padding(.trailing, 12).padding(.top, 22)
            }
    }

    private var header: some View {
        HStack {
            Text("mAIverse").font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer()
            Button(action: openDetails) { Image(systemName: "gearshape").font(.system(size: 20)).frame(width: 38, height: 38) }
                .accessibilityLabel("角色与AI设置")
            Button(action: openCharacters) { CharacterAvatar(character: store.displayCharacter, size: 32).padding(4) }
                .accessibilityLabel("查看角色")
            Button(action: openDetails) { Image(systemName: "info.circle").frame(width: 32, height: 38) }
                .accessibilityLabel("查看大肥鱼角色详情")
                .accessibilityIdentifier("worldCharacterCard")
                .accessibilityValue(store.worldArtwork(for: store.displayCharacter).id)
        }
        .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.25))
        .buttonStyle(.plain)
    }

    private var shortcutDivider: some View {
        Color(red: 0.16, green: 0.22, blue: 0.34).opacity(0.12)
            .frame(width: 18, height: 0.5).accessibilityHidden(true)
    }

    private func shortcut(_ title: String, symbol: String, panel destination: Panel) -> some View {
        Button { panel = destination } label: {
            VStack(spacing: 3) {
                if destination == .island {
                    ZStack {
                        Capsule().stroke(lineWidth: 1.4).frame(width: 21, height: 10)
                        Capsule().frame(width: 7, height: 2)
                    }.frame(height: 21)
                } else {
                    Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(height: 21)
                }
                Text(title).font(.system(size: 9))
            }.frame(width: 44, height: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.25))
            .accessibilityLabel(destination == .island ? "灵动岛预览" : title)
            .accessibilityIdentifier("homeShortcut-\(destination.rawValue)")
    }

    private func greet() {
        guard !requesting else { return }
        replay += 1; requesting = true; greetingError = false; greeting = nil
        greetingTask = Task { @MainActor in
            defer { requesting = false; greetingTask = nil }
            do {
                let line = try await chat.homeGreeting(for: store.displayCharacter)
                try Task.checkCancellation()
                greeting = line
            } catch is CancellationError { }
            catch { if !Task.isCancelled { greetingError = true } }
        }
    }

    private func cancelGreeting() { greetingTask?.cancel() }
}
