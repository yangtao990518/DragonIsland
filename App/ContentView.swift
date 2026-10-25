import SwiftUI

struct ContentView: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var minutes = 25
    @State private var floating = false

    var body: some View {
        ZStack {
            DragonPalette.ink.ignoresSafeArea()
            RadialGradient(colors: [Color.purple.opacity(0.19), .clear],
                           center: .init(x: 0.5, y: 0.25), startRadius: 0, endRadius: 330)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    header
                    hero
                    if let session = store.session {
                        activeCard(session)
                    } else {
                        setupCard
                    }
                    islandPreview
                    Text("主 App 内有轻微待机动画；灵动岛显示静态角色和状态变化。\n本地运行，无需 AI 账号或 API Key。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                    Text("ChatGPT 龙娘同人试验 · 非官方应用")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .tint(DragonPalette.lavender)
        .alert("小白的提示", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("知道了", role: .cancel) { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(DragonPalette.lavender)
                Text("岛上龙娘").font(.headline)
            }
            Spacer()
            Text("PROTOTYPE 01")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DragonPalette.lavender.opacity(0.07))
                    .frame(width: 220, height: 220)
                Circle()
                    .stroke(DragonPalette.lavender.opacity(0.15), lineWidth: 1)
                    .frame(width: 205, height: 205)
                Image("DragonHero")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 238)
                    .offset(y: reduceMotion ? 0 : (floating ? -4 : 4))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: floating)
                    .accessibilityLabel("白发、紫眼睛，带着小翅膀和龙尾巴的小白")
                    .onAppear { floating = true }
            }
            Text("让今天，轻一点。")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(DragonPalette.softWhite)
            Text("小白会在岛上，陪你待一会儿。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(.top, 8)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("这次陪伴多久", systemImage: "hourglass")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("1 分钟可快速测试").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach([1, 25, 50, 120], id: \.self) { value in
                    Button { minutes = value } label: {
                        VStack(spacing: 4) {
                            Text("\(value)").font(.system(size: 22, weight: .semibold, design: .rounded))
                            Text("分钟").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(minutes == value ? DragonPalette.lavender : Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 15))
                        .foregroundStyle(minutes == value ? DragonPalette.ink : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("陪伴 \(value) 分钟")
                    .accessibilityAddTraits(minutes == value ? .isSelected : [])
                }
            }
            Button {
                Task { await store.start(minutes: minutes) }
            } label: {
                HStack {
                    if store.busy { ProgressView().tint(DragonPalette.ink) }
                    Image(systemName: "sparkles")
                    Text("开始陪伴").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(DragonPalette.ink)
                .background(DragonPalette.lavender, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(store.busy)
        }
        .padding(20)
        .cardStyle()
    }

    private func activeCard(_ session: CompanionSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let expired = session.hasExpired(at: timeline.date)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(expired ? "这轮陪伴已完成" : session.mood.title,
                          systemImage: expired ? "checkmark.circle.fill" : session.mood.symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DragonPalette.lavender)
                    Spacer()
                    DragonCountdown(state: session, expired: expired)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .frame(width: 100, alignment: .trailing)
                }
                Text(expired ? "辛苦啦。休息一下，再一起出发。" : session.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !expired {
                    HStack(spacing: 10) {
                        actionButton("打个招呼", icon: "hand.wave.fill") { await store.greet() }
                        actionButton("换个心情", icon: "sparkles") { await store.changeMood() }
                    }
                }
                Button {
                    Task { await store.finish() }
                } label: {
                    Text(expired ? "收起这一轮" : "结束本轮陪伴")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .disabled(store.busy)
            }
            .padding(20)
            .cardStyle()
        }
    }

    private func actionButton(_ title: String, icon: String,
                              action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(store.busy)
    }

    private var islandPreview: some View {
        VStack(spacing: 12) {
            Text("岛上会是这样")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 12) {
                DragonPortrait()
                Capsule().fill(.white.opacity(0.035)).frame(width: 74, height: 20)
                if let state = store.session {
                    DragonCountdown(state: state)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .frame(width: 48)
                } else {
                    Text(String(format: "%02d:00", minutes))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 48)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 42)
            .background(.black, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
            .fixedSize()
            Text("开始后回到桌面查看 · 长按灵动岛展开互动")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}
