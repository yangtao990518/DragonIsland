import SwiftUI

struct HomeGameButtonLabel: View {
    let style: HomeButtonStyle
    let kind: HomeShortcutKind
    let character: CompanionCharacter

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if character.id == "dafeiyu" {
                    Image(style.assetPrefix + kind.assetSuffix).resizable().scaledToFit()
                } else {
                    // Other residents use their own artwork, not Dafeiyu's portrait.
                    ResidentGameBadge(style: style, kind: kind, character: character)
                }
                Text(kind.title)
                    .font(.system(size: geometry.size.width * 0.15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.30))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: geometry.size.width * 0.49)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.84)
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct HomeGameShortcutRail: View {
    let style: HomeButtonStyle
    let character: CompanionCharacter
    let open: (HomeShortcutKind) -> Void
    var size: CGFloat = 72
    var body: some View {
        VStack(spacing: 3) {
            ForEach(HomeShortcutKind.allCases) { kind in
                Button { open(kind) } label: {
                    HomeGameButtonLabel(style: style, kind: kind, character: character)
                        .frame(width: size, height: size).contentShape(Rectangle())
                }
                .buttonStyle(GameShortcutPressStyle())
                .accessibilityLabel(kind.accessibilityTitle)
                .accessibilityIdentifier("homeShortcut-\(kind.rawValue)")
            }
        }
    }
}

private struct GameShortcutPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CharacterHomeButtonStylePicker: View {
    @ObservedObject var store: CompanionStore
    let character: CompanionCharacter
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("主页按钮风格").font(.headline)
            Text("只更改\(character.name)的按钮，其他角色会保留自己的选择。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                ForEach(HomeButtonStyle.allCases) { style in
                    let selected = store.homeButtonStyle(for: character) == style
                    Button { store.setHomeButtonStyle(style, for: character) } label: {
                        VStack(spacing: 10) {
                            HStack(spacing: 1) {
                                ForEach(HomeShortcutKind.allCases) { kind in
                                    HomeGameButtonLabel(style: style, kind: kind, character: character)
                                }
                            }.frame(height: 52)
                            Label(style.title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .padding(10).frame(maxWidth: .infinity)
                        .background(selected ? AppPalette.accent.opacity(0.08) : Color.primary.opacity(0.025),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(selected ? AppPalette.accent : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(.plain).foregroundStyle(selected ? AppPalette.accent : .primary)
                    .accessibilityIdentifier("homeButtonStyle-\(character.id)-\(style.rawValue)")
                    .accessibilityValue(selected ? "已选择" : "未选择")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }.worldCard().accessibilityIdentifier("characterHomeButtonStyles")
    }
}

struct HomeShortcutPanel: View {
    @ObservedObject var store: CompanionStore
    let character: CompanionCharacter
    let kind: HomeShortcutKind
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .actions: MotionSettingsView(store: store, character: character)
                case .scene: WorldPage { IslandScenePicker(store: store) }
                case .island:
                    WorldPage {
                        PageHeading(eyebrow: "LIVE ACTIVITY", title: "灵动岛预览", subtitle: "开始陪伴后回到桌面，长按灵动岛展开。")
                        IslandArtPreview(character: character, expanded: false, scene: store.islandScene)
                        IslandArtPreview(character: character, expanded: true, scene: store.islandScene)
                    }
                }
            }
            .navigationTitle(kind == .actions ? "日常动作" : kind == .scene ? "灵动岛场景" : "灵动岛预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }.accessibilityIdentifier("closeHomePanel")
            } }
        }
    }
}

/// Shared native framing for new residents without a dedicated illustrated badge set yet.
private struct ResidentGameBadge: View {
    let style: HomeButtonStyle
    let kind: HomeShortcutKind
    let character: CompanionCharacter
    private var candyColor: Color {
        switch kind { case .actions: return Color(red: 0.36, green: 0.84, blue: 0.88)
        case .scene: return Color(red: 1, green: 0.64, blue: 0.56)
        case .island: return Color(red: 0.72, green: 0.59, blue: 0.98) }
    }
    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            ZStack {
                if style == .fantasy {
                    GameShield().fill(LinearGradient(colors: [Color(red: 0.20, green: 0.28, blue: 0.58), Color(red: 0.08, green: 0.14, blue: 0.34)], startPoint: .top, endPoint: .bottom))
                        .overlay(GameShield().stroke(Color(red: 0.84, green: 0.64, blue: 0.30), lineWidth: 2))
                        .padding(side * 0.07)
                } else {
                    RoundedRectangle(cornerRadius: side * 0.22).fill(candyColor.gradient)
                        .overlay(RoundedRectangle(cornerRadius: side * 0.22).stroke(.white.opacity(0.8), lineWidth: 1.2))
                        .padding(side * 0.08)
                }
                Group {
                    if kind == .scene {
                        Image(systemName: "cloud.sun.fill").symbolRenderingMode(.palette)
                            .foregroundStyle(.yellow, .white).font(.system(size: side * 0.34))
                    } else if kind == .island {
                        Image(character.chibiAsset + "Detail").resizable().scaledToFit()
                            .padding(side * 0.015)
                            .background(Color(red: 0.72, green: 0.85, blue: 0.98), in: RoundedRectangle(cornerRadius: side * 0.06))
                            .overlay(RoundedRectangle(cornerRadius: side * 0.06).stroke(Color(red: 0.12, green: 0.17, blue: 0.30), lineWidth: 2))
                    } else { Image(character.chibiAsset + "Detail").resizable().scaledToFit() }
                }
                .frame(width: side * 0.60, height: side * 0.55)
                .position(x: side * 0.5, y: side * 0.41)
                RoundedRectangle(cornerRadius: side * 0.07)
                    .fill(Color(red: 1, green: 0.95, blue: 0.82))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.07).stroke(style == .fantasy ? Color(red: 0.83, green: 0.63, blue: 0.31) : .white, lineWidth: 1))
                    .frame(width: side * 0.73, height: side * 0.22)
                    .position(x: side * 0.5, y: side * 0.84)
            }
        }
    }
}

private struct GameShield: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.80))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.height * 0.90))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.80), control: CGPoint(x: rect.minX, y: rect.height * 0.90))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.16))
        path.closeSubpath()
        return path
    }
}
