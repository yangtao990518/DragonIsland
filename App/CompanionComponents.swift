import SwiftUI

struct WorldPage<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ZStack {
            AppPalette.background.ignoresSafeArea()
            LinearGradient(colors: [AppPalette.accent.opacity(0.08), .clear],
                           startPoint: .topLeading, endPoint: .center).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Color.primary)
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(2).foregroundStyle(AppPalette.accent)
            Text(title).font(.system(size: 29, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
        }.padding(.vertical, 8)
    }
}

struct CharacterHero: View {
    let character: CompanionCharacter
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    private var shouldAnimate: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--maiverse-capture") { return false }
        #endif
        return !reduceMotion
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [AppPalette.hero, AppPalette.surface],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(AppPalette.accent.opacity(0.07))
                    .frame(width: 250, height: 250).offset(x: 75, y: 5)
                Circle().stroke(AppPalette.accent.opacity(0.13), lineWidth: 1)
                    .frame(width: 232, height: 232).offset(x: 65, y: 2)
                Image(systemName: "sparkle")
                    .font(.system(size: 16)).foregroundStyle(AppPalette.accent.opacity(0.6))
                    .position(x: geometry.size.width * 0.48, y: 44)
                Image(character.heroAsset)
                    .resizable().scaledToFit()
                    .frame(width: geometry.size.width * 0.60, height: 294)
                    .offset(x: 6, y: shouldAnimate ? (floating ? -4 : 2) : 0)
                    .animation(shouldAnimate ? .easeInOut(duration: 2.8).repeatForever(autoreverses: true) : nil,
                               value: floating)
                    .accessibilityLabel("\(character.name)的完整立绘")
                VStack(alignment: .leading, spacing: 0) {
                    Text("YOUR LITTLE\nUNIVERSE")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(2).lineSpacing(4).foregroundStyle(AppPalette.accent.opacity(0.85))
                    Text("你的世界，\n今天也有我。")
                        .font(.system(size: 25, weight: .semibold)).lineSpacing(5)
                        .padding(.top, 17)
                    Spacer()
                    Text(character.name).font(.system(size: 21, weight: .semibold))
                    Text(character.subtitle).font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.48)).padding(.top, 5)
                    HStack(spacing: 5) {
                        Circle().fill(AppPalette.status).frame(width: 4, height: 4)
                        Text(active ? "正在陪你" : "等你一起出发").font(.system(size: 9))
                    }
                    .foregroundStyle(AppPalette.status)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(AppPalette.status.opacity(0.08), in: Capsule()).padding(.top, 13)
                }
                .frame(width: geometry.size.width * 0.48, alignment: .leading)
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 27))
            .overlay(RoundedRectangle(cornerRadius: 27).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .frame(height: 310)
        .onAppear { floating = true }
    }
}

struct CompanionAction: View {
    let title: String
    let symbol: String
    let disabled: Bool
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 43)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).foregroundStyle(AppPalette.accent).disabled(disabled)
    }
}

struct IslandArtPreview: View {
    let character: CompanionCharacter
    let expanded: Bool

    var body: some View {
        Group {
            if expanded {
                HStack(spacing: 12) {
                    CharacterStanding(character: character, width: 58, height: 80)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(character.name).foregroundStyle(DragonPalette.lavender)
                            Spacer()
                            Text("24:59").monospacedDigit()
                        }.font(.system(size: 11, weight: .medium))
                        Text(character.introduction).font(.system(size: 11)).lineLimit(2)
                        HStack(spacing: 5) {
                            ForEach(["招呼", "心情", "结束"], id: \.self) { title in
                                Text(title).font(.system(size: 9))
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .foregroundStyle(DragonPalette.lavender)
                                    .background(DragonPalette.lavender.opacity(0.18), in: Capsule())
                            }
                        }.accessibilityHidden(true)
                    }
                }
                .padding(14).background(.black, in: RoundedRectangle(cornerRadius: 27))
            } else {
                HStack(spacing: 10) {
                    DragonPortrait(character: character, size: 26)
                    Capsule().fill(Color.white.opacity(0.025)).frame(width: 66, height: 22)
                    Text("24:59").font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DragonPalette.lavender)
                }
                .padding(.horizontal, 13).frame(height: 42).background(.black, in: Capsule())
            }
        }
        .foregroundStyle(DragonPalette.softWhite)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(expanded ? "展开态示意，显示立绘" : "紧凑态示意，显示 Q 版小人物")
    }
}

struct CharacterResidentCard: View {
    let character: CompanionCharacter
    let selected: Bool
    let active: Bool
    let open: () -> Void
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 17) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [AppPalette.accent.opacity(0.12), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(character.heroAsset).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: 285).padding(.top, 12)
                VStack(spacing: 5) {
                    DragonPortrait(character: character, size: 48)
                    Text("岛上形象").font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.5))
                }
                .padding(12).background(AppPalette.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 17))
                .padding(13)
            }
            .frame(height: 302).clipShape(RoundedRectangle(cornerRadius: 20))
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(character.name).font(.system(size: 22, weight: .semibold))
                        Text(character.subtitle).font(.system(size: 11)).foregroundStyle(AppPalette.accent)
                    }
                    Text(character.origin).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                if selected { Image(systemName: "checkmark.seal.fill").foregroundStyle(AppPalette.status) }
            }
            Text("“\(character.introduction)”")
                .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.65))
            Label("查看角色与图片", systemImage: "arrow.up.right")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppPalette.accent)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("characterCard-\(character.id)")
            Button(action: select) {
                Text(selected ? (active ? "正在你的世界里陪你" : "已选择 · 随时可以出发") : "邀请\(character.name)陪伴")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .foregroundStyle(selected ? AppPalette.status : AppPalette.background)
                    .background(selected ? AppPalette.status.opacity(0.08) : AppPalette.accent,
                                in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain).disabled(active || selected)
        }.worldCard()
    }
}

extension View {
    func worldCard() -> some View {
        padding(18)
            .background(AppPalette.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.primary.opacity(0.055), lineWidth: 1))
    }
}
