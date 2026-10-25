import SwiftUI

/// Uses system-rendered timer glyphs; contains no Timer, Task loop or Activity.update.
/// Layering technique adapted from MIT WidgetAnimation by Bryce Bostwick.
struct TimerMotionPortrait: View {
    let plan: Int
    let epoch: Date
    let endsAt: Date
    let size: CGFloat

    private var reference: Date { epoch.addingTimeInterval(-60) }
    var body: some View {
        ZStack {
            ZStack {
                layer(0)
                ForEach(1..<8, id: \.self) { index in
                    layer(index).mask(gate(offset: -Double(index) / 8))
                }
            }
            ZStack {
                ForEach(8..<16, id: \.self) { index in
                    layer(index).mask(gate(offset: -Double(index) / 8))
                }
            }.mask(gate(offset: 1))
        }
        .frame(width: size, height: size).clipped()
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .accessibilityHidden(true)
    }
    private func layer(_ index: Int) -> some View {
        timerGlyph(font: "mAIverseP\(plan)F\(index)", offset: 1 + Double(index) / 8)
    }
    private func gate(offset: Double) -> some View {
        timerGlyph(font: "mAIverseGate", offset: -offset).foregroundStyle(.white)
    }
    private func timerGlyph(font: String, offset: Double) -> some View {
        Text(timerInterval: reference.addingTimeInterval(offset)...endsAt, countsDown: false)
            .font(.custom(font, fixedSize: size))
            .contentTransition(.identity)
            .frame(width: size * 9, height: size)
            .multilineTextAlignment(.trailing)
            .offset(x: -size * 4)
    }
}
