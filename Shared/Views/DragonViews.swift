import SwiftUI

enum DragonPalette {
    static let ink = Color(red: 0.055, green: 0.043, blue: 0.090)
    static let lavender = Color(red: 0.77, green: 0.68, blue: 0.96)
    static let softWhite = Color(red: 0.96, green: 0.94, blue: 1.0)
    static let mint = Color(red: 0.72, green: 0.91, blue: 0.83)
    static let surface = Color(red: 0.10, green: 0.085, blue: 0.15)
}

struct DragonPortrait: View {
    var character: CompanionCharacter = .xiaobai
    var size: CGFloat = 22

    var body: some View {
        Image(character.chibiAsset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("\(character.name)的 Q 版形象")
    }
}

struct CharacterStanding: View {
    let character: CompanionCharacter
    var width: CGFloat = 72
    var height: CGFloat = 96

    var body: some View {
        Image(character.portraitAsset)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .accessibilityLabel("\(character.name)的立绘")
    }
}

struct IslandMotionPortrait: View {
    let character: CompanionCharacter
    let state: CompanionSession
    var size: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        ZStack {
            Image(state.islandScene.asset).resizable()
            if character.id == "xiaobai", let plan = state.automaticMotionPlan,
               (0..<8).contains(plan), !reduceMotion, !luminanceReduced {
                TimerMotionPortrait(plan: plan, epoch: state.motionEpoch ?? state.startedAt,
                                    endsAt: state.endsAt, size: size + 8, scene: state.islandScene)
            } else {
                DragonPortrait(character: character, size: size)
            }
        }.frame(width: (size + 8) * 1.875, height: size + 8)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            // A scene uses a different timer-font family. Reusing native text
            // identities can retain its old font until another presentation
            // refreshes. Replace the scene atomically, without a pose crossfade.
            .id(state.islandScene.rawValue)
            .transition(.identity)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

struct IslandSceneBackdrop: View {
    let scene: IslandScene
    var body: some View {
        Image(scene.asset).resizable().scaledToFill().clipped().accessibilityHidden(true)
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
