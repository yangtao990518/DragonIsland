import SwiftUI

enum DragonPalette {
    static let ink = Color(red: 0.055, green: 0.043, blue: 0.090)
    static let lavender = Color(red: 0.77, green: 0.68, blue: 0.96)
    static let softWhite = Color(red: 0.96, green: 0.94, blue: 1.0)
}

struct DragonPortrait: View {
    var size: CGFloat = 22

    var body: some View {
        Image("DragonCompact")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("白紫色小龙娘")
    }
}

struct DragonCountdown: View {
    let state: CompanionSession
    var expired: Bool = false

    var body: some View {
        Group {
            if expired {
                Text("00:00")
            } else {
                // System-rendered timer; no background Timer or per-second pushes.
                Text(timerInterval: state.timerRange, countsDown: true)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .contentTransition(.numericText())
        .accessibilityLabel("陪伴剩余时间")
    }
}
