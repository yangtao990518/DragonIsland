import SwiftUI

enum MoonPalette {
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.93)
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.32)
    static let violet = Color(red: 0.42, green: 0.29, blue: 0.76)
    static let lavender = Color(red: 0.79, green: 0.75, blue: 0.92)
    static let gold = Color(red: 0.76, green: 0.60, blue: 0.38)
}

/// Decorative artwork only. All text, tabs, fields and buttons remain native views.
struct MoonBackdrop: View {
    var night = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: night
                    ? [Color(red: 0.17, green: 0.18, blue: 0.38), Color(red: 0.38, green: 0.33, blue: 0.59)]
                    : [MoonPalette.paper, Color(red: 0.94, green: 0.91, blue: 0.98), MoonPalette.paper],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(MoonPalette.gold.opacity(0.30), lineWidth: 1)
                    .frame(width: geometry.size.width * 1.13, height: geometry.size.width * 1.13)
                    .offset(x: geometry.size.width * 0.24, y: -geometry.size.height * 0.15)
                Circle().stroke(.white.opacity(night ? 0.13 : 0.8), lineWidth: 14)
                    .frame(width: geometry.size.width * 1.03, height: geometry.size.width * 1.03)
                    .offset(x: geometry.size.width * 0.24, y: -geometry.size.height * 0.15)
                Canvas { context, size in
                    for side in 0..<2 {
                        let sign: CGFloat = side == 0 ? 1 : -1
                        let origin: CGFloat = side == 0 ? 8 : size.width - 8
                        for branch in 0..<5 {
                            let x = origin + sign * CGFloat(branch * 18)
                            let base = size.height - CGFloat(branch * 8)
                            var stem = Path()
                            stem.move(to: CGPoint(x: x, y: base))
                            stem.addQuadCurve(to: CGPoint(x: x + sign * 24, y: base - 120 - CGFloat(branch * 10)),
                                              control: CGPoint(x: x - sign * 18, y: base - 72))
                            context.stroke(stem, with: .color(MoonPalette.lavender.opacity(0.65)), lineWidth: 1)
                            for leaf in 0..<5 {
                                let cy = base - CGFloat(leaf * 22) - 12
                                let direction: CGFloat = leaf.isMultiple(of: 2) ? sign : -sign
                                var shape = Path()
                                shape.move(to: CGPoint(x: x, y: cy))
                                shape.addQuadCurve(to: CGPoint(x: x + direction * 24, y: cy - 23), control: CGPoint(x: x + direction * 32, y: cy - 2))
                                shape.addQuadCurve(to: CGPoint(x: x, y: cy), control: CGPoint(x: x + direction * 2, y: cy - 22))
                                context.fill(shape, with: .color(MoonPalette.lavender.opacity(night ? 0.24 : 0.38)))
                            }
                        }
                    }
                    for index in 0..<19 {
                        let x = CGFloat((index * 83 + 17) % 337) / 337 * size.width
                        let y = CGFloat((index * 131 + 23) % 457) / 457 * size.height
                        let r: CGFloat = index.isMultiple(of: 3) ? 6 : 3
                        var star = Path()
                        star.move(to: CGPoint(x: x, y: y - r))
                        star.addLine(to: CGPoint(x: x + r * 0.25, y: y - r * 0.25))
                        star.addLine(to: CGPoint(x: x + r, y: y))
                        star.addLine(to: CGPoint(x: x + r * 0.25, y: y + r * 0.25))
                        star.addLine(to: CGPoint(x: x, y: y + r))
                        star.addLine(to: CGPoint(x: x - r * 0.25, y: y + r * 0.25))
                        star.addLine(to: CGPoint(x: x - r, y: y))
                        star.addLine(to: CGPoint(x: x - r * 0.25, y: y - r * 0.25))
                        star.closeSubpath()
                        context.fill(star, with: .color(MoonPalette.gold.opacity(0.5)))
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct MoonCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(MoonPalette.gold.opacity(0.25), lineWidth: 1))
    }
}

struct MoonPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 17, weight: .semibold, design: .serif))
            .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
            .background(LinearGradient(colors: [MoonPalette.violet, Color(red: 0.29, green: 0.22, blue: 0.59)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            .overlay(Capsule().inset(by: 3).stroke(MoonPalette.gold.opacity(0.85), lineWidth: 1))
            .shadow(color: MoonPalette.violet.opacity(0.15), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct MoonIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44).background(.white.opacity(0.88), in: Circle())
                .overlay(Circle().stroke(MoonPalette.gold.opacity(0.25), lineWidth: 1))
                .shadow(color: MoonPalette.ink.opacity(0.06), radius: 6, y: 3)
        }.buttonStyle(.plain).foregroundStyle(MoonPalette.violet).accessibilityLabel(label)
    }
}
