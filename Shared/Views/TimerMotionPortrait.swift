import SwiftUI

/// Uses system-rendered timer glyphs; contains no Timer, Task loop or Activity.update.
/// Layering technique adapted from MIT WidgetAnimation by Bryce Bostwick.
struct TimerMotionPortrait: View {
    let plan: Int
    let epoch: Date
    let endsAt: Date
    let size: CGFloat
    var scene: IslandScene = .black
    var character: CompanionCharacter = .xiaobai
    private var width: CGFloat { size * 1.875 }

    private var reference: Date { epoch.addingTimeInterval(-60) }
    private var framesPerSecond: Int { MotionTimeline.shared?.fps ?? 30 }
    var body: some View {
        ZStack {
            ZStack {
                layer(0)
                ForEach(1..<framesPerSecond, id: \.self) { index in
                    layer(index).mask(gate(offset: -Double(index) / Double(framesPerSecond)))
                }
            }
            ZStack {
                ForEach(framesPerSecond..<(framesPerSecond * 2), id: \.self) { index in
                    layer(index).mask(gate(offset: -Double(index) / Double(framesPerSecond)))
                }
            }.mask(gate(offset: 1))
        }
        .frame(width: width, height: size).clipped()
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .accessibilityHidden(true)
    }
    private func layer(_ index: Int) -> some View {
        let prefix = character.motionProfile?.fontPrefix ?? "mAIverse"
        let suffix = String(scene.fontPrefix.dropFirst("mAIverse".count))
        let font = Font.custom("\(prefix)\(suffix)F\(index)", fixedSize: size)
        // All banks share the phase font. Hidden hours select an action bank;
        // banks in font shaping; the maximum two-hour session stays in its bank.
        // Prepare the next glyph one phase BEFORE its gate opens. Native timer
        // texts and masks can commit separately; changing both at the same
        // boundary briefly exposed the previous second's pose in system video.
        // Earlier layers cover this preload until the scheduled gate opens.
        let preload = 1 / Double(framesPerSecond)
        return timerGlyph(font: font, offset: 1 + Double(index) / Double(framesPerSecond) - Double(plan * 3 * 3600) - preload)
    }
    private func gate(offset: Double) -> some View {
        timerGlyph(font: .custom("mAIverseGate", fixedSize: size), offset: -offset).foregroundStyle(.white)
    }
    private func timerGlyph(font: Font, offset: Double) -> some View {
        Text(timerInterval: reference.addingTimeInterval(offset)...endsAt, countsDown: false)
            .font(font)
            .contentTransition(.identity)
            .frame(width: width * 9, height: size)
            .multilineTextAlignment(.trailing)
            .offset(x: -width * 4)
    }
}

