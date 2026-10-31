import SwiftUI

/// System-rendered timer glyphs, using the existing phase-gate technique.
/// No app timer, repeatForever animation or per-frame Live Activity updates.
struct UnreadTimerAvatar: View {
    let character: CompanionCharacter
    let epoch: Date
    var size: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var lowLight
    private let fps = 8
    private var width: CGFloat { size * 1.875 }
    private var reference: Date { epoch.addingTimeInterval(-60) }
    private var ends: Date { epoch.addingTimeInterval(8 * 3600) }
    private var prefix: String { character.id == "dafeiyu" ? "mAIverseUnreadDafeiyu" : "mAIverseUnreadXiaobai" }
    var body: some View {
        Group {
            if reduceMotion || lowLight || !["xiaobai", "dafeiyu"].contains(character.id) {
                CharacterAvatar(character: character, size: size * 0.84).frame(width: width, height: size)
            } else {
                ZStack {
                    ZStack {
                        layer(0)
                        ForEach(1..<fps, id: \.self) { i in layer(i).mask(gate(-Double(i) / Double(fps))) }
                    }
                    ZStack {
                        ForEach(fps..<(fps * 2), id: \.self) { i in layer(i).mask(gate(-Double(i) / Double(fps))) }
                    }.mask(gate(1))
                }.frame(width: width, height: size).clipped()
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(character.name)的头像")
    }
    private func layer(_ index: Int) -> some View {
        glyph(font: .custom("\(prefix)F\(index)", fixedSize: size), offset: 1 + Double(index) / Double(fps) - 1 / Double(fps))
    }
    private func gate(_ offset: Double) -> some View { glyph(font: .custom("mAIverseGate", fixedSize: size), offset: -offset).foregroundStyle(.white) }
    private func glyph(font: Font, offset: Double) -> some View {
        Text(timerInterval: reference.addingTimeInterval(offset)...ends, countsDown: false)
            .font(font).contentTransition(.identity).frame(width: width * 9, height: size)
            .multilineTextAlignment(.trailing).offset(x: -width * 4)
    }
}
