import SwiftUI
import UIKit

private enum WorldTab: Hashable {
    case world, characters, about

    static var initial: WorldTab {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-characters") { return .characters }
        if ProcessInfo.processInfo.arguments.contains("--preview-about") { return .about }
        #endif
        return .world
    }
}

struct ContentView: View {
    @ObservedObject var store: CompanionStore
    @State private var tab = WorldTab.initial
    @State private var minutes = 25
    @State private var expandedPreview = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView(selection: $tab) {
            worldPage
                .tabItem { Label("我的世界", systemImage: "sparkles") }.tag(WorldTab.world)
            charactersPage
                .tabItem { Label("角色", systemImage: "person.2") }.tag(WorldTab.characters)
            aboutPage
                .tabItem { Label("关于", systemImage: "circle.grid.2x2") }.tag(WorldTab.about)
        }
        .tint(DragonPalette.lavender)
        .toolbarBackground(DragonPalette.ink, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .alert("mAIverse", isPresented: Binding(
            get: { store.notice != nil }, set: { if !$0 { store.notice = nil } }
        )) {
            Button("知道了", role: .cancel) { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }

    private var worldPage: some View {
        WorldPage {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("mAIverse").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("你的世界，他们也在。")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                Button { tab = .characters } label: {
                    DragonPortrait(character: store.displayCharacter, size: 32)
                        .padding(7)
                        .background(.white.opacity(0.06), in: Circle())
                        .overlay(Circle().stroke(DragonPalette.lavender.opacity(0.35), lineWidth: 1))
                }
                .accessibilityLabel("查看角色")
            }
            CharacterHero(character: store.displayCharacter, active: store.session != nil)
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
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
    }

    private var setupSession: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("这次，陪你多久？").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("1 分钟体验").font(.system(size: 10)).foregroundStyle(DragonPalette.mint)
            }
            HStack(spacing: 8) {
                ForEach([1, 25, 50, 120], id: \.self) { value in
                    Button { minutes = value } label: {
                        VStack(spacing: 3) {
                            Text("\(value)").font(.system(size: 23, weight: .semibold, design: .rounded))
                            Text("分钟").font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(minutes == value ? DragonPalette.ink : DragonPalette.softWhite)
                        .background(minutes == value ? DragonPalette.lavender : .white.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("陪伴 \(value) 分钟")
                    .accessibilityAddTraits(minutes == value ? .isSelected : [])
                }
            }
            Button { Task { await store.start(minutes: minutes) } } label: {
                HStack(spacing: 8) {
                    if store.busy { ProgressView().tint(DragonPalette.ink) }
                    Image(systemName: "sparkles")
                    Text("让\(store.selectedCharacter.name)陪着我").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14))
                .padding(.horizontal, 17).frame(height: 48)
                .foregroundStyle(DragonPalette.ink)
                .background(DragonPalette.lavender, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain).disabled(store.busy)
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
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(DragonPalette.mint)
                        Text(expired ? "辛苦啦，休息一下吧。" : session.mood.title)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer(minLength: 8)
                    DragonCountdown(state: session, expired: expired)
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .frame(width: 108, alignment: .trailing)
                }
                Text(expired ? "下一段时间，也可以一起度过。" : session.message)
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
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
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
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
                Text("界面示意").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            Picker("预览形态", selection: $expandedPreview) {
                Text("日常 · 小人物").tag(false)
                Text("展开 · 立绘").tag(true)
            }.pickerStyle(.segmented)
            IslandArtPreview(character: store.displayCharacter, expanded: expandedPreview)
                .frame(maxWidth: .infinity)
            Text("开始陪伴后回到桌面，长按灵动岛展开。")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
        .worldCard()
    }

    private var charactersPage: some View {
        WorldPage {
            PageHeading(eyebrow: "RESIDENTS", title: "住进你的世界", subtitle: "小小的身影，也有完整的模样。")
            ForEach(store.characters) { character in
                CharacterResidentCard(character: character,
                                      selected: store.selectedCharacter.id == character.id,
                                      active: store.session != nil) { store.select(character) }
            }
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(DragonPalette.lavender)
                Text("这里会慢慢热闹起来。")
                    .font(.system(size: 16, weight: .medium))
                Text("更多角色，等待与你相遇。")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            if store.session != nil {
                Text("结束本轮陪伴后，可以切换住民。")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var aboutPage: some View {
        WorldPage {
            PageHeading(eyebrow: "ABOUT YOUR WORLD", title: "mAIverse", subtitle: "My + AI + Universe · 我的 AI 小世界")
            VStack(alignment: .leading, spacing: 17) {
                Text("你的世界，他们也在。")
                    .font(.system(size: 21, weight: .semibold))
                Text("让喜欢的角色住进手机，陪你专注，也陪你放松。小白是这里的第一位住民。")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65)).lineSpacing(5)
                Divider().overlay(.white.opacity(0.08))
                Label("当前为本地陪伴，互动短句为预设内容。", systemImage: "iphone")
                Label("尚未接入 AI 对话，无需账号或 API Key。", systemImage: "lock")
                Label("到时不会自动响铃，可手动结束陪伴。", systemImage: "hourglass")
            }
            .font(.system(size: 12)).foregroundStyle(DragonPalette.softWhite)
            .worldCard()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                HStack {
                    Label("实时活动与系统设置", systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14)).foregroundStyle(DragonPalette.lavender)
            }.worldCard()
            VStack(spacing: 7) {
                Text("mAIverse \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")")
                Text("角色为非官方同人形象，与相关 AI 服务提供方无隶属关系。")
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }
}
