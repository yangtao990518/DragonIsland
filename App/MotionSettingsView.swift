import SwiftUI

struct MotionSettingsView: View {
    @ObservedObject var store: CompanionStore
    @State private var previewAction = "random"
    var body: some View {
        WorldPage {
            HStack {
                PageHeading(eyebrow: "DAILY LIFE", title: "\(store.displayCharacter.name)的日常", subtitle: "挑选喜欢的小动作，让她自己玩一会儿。")
                Spacer(minLength: 0)
                AppearanceToggle()
            }
            VStack(spacing: 12) {
                MotionArtworkPreview(settings: store.motionSettings, action: previewAction, scene: store.islandScene, character: store.displayCharacter)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                Picker("动作预览", selection: $previewAction) {
                    Text("随机").tag("random")
                    Text("待机").tag("idle")
                    Text("右走").tag("walk_right")
                    Text("左走").tag("walk_left")
                    Text("打滚").tag("roll")
                }.pickerStyle(.segmented)
                Text("动作预览").font(.caption).foregroundStyle(.secondary)
                Text("轻点小人物，和她打个招呼。")
                    .font(.caption).foregroundStyle(.secondary)
            }.worldCard()
            VStack(alignment: .leading, spacing: 17) {
                Toggle("自动活动", isOn: binding(\.automatic))
                    .accessibilityIdentifier("automaticMotionToggle")
                Text("开始陪伴后回到桌面，无需再点动作按钮。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Toggle("走路 · 走到边边再回来", isOn: binding(\.walk))
                    .accessibilityIdentifier("walkMotionToggle")
                Toggle("打滚 · 向两边滚，再回来", isOn: binding(\.roll))
                    .accessibilityIdentifier("rollMotionToggle")
                Text("走路会慢慢迈步，约 10 秒走到另一端，再折返回来。打滚也会向左、向右移动，约 5 秒一个方向。未勾选的动作不会参与，都不勾选时只待机。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }.disabled(store.busy).worldCard()
            Text("设置会保存并应用当前陪伴。本版日常片段为 60 秒循环；减弱动态效果或息屏低亮度时显示静态人物。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func binding(_ key: WritableKeyPath<MotionSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.motionSettings[keyPath: key] }, set: { value in
            var settings = store.motionSettings
            settings[keyPath: key] = value
            Task { await store.setMotionSettings(settings) }
        })
    }
}

struct MotionArtworkPreview: View {
    let settings: MotionSettings
    var action = "random"
    var scene: IslandScene = .black
    var character: CompanionCharacter = .xiaobai
    @State private var began = Date()
    @State private var reactionBegan: Date?
    @State private var reactionX = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
          let width = min(geometry.size.width - 12, 330)
          TimelineView(.animation(minimumInterval: 1.0 / Double(MotionTimeline.shared?.fps ?? 30), paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(began)
            ZStack {
              Image(scene.asset).resizable()
            if let frame = frame(elapsed: elapsed, at: context.date) {
                Image(frame.asset).resizable().scaledToFit()
                    .frame(width: width * 72 / 180, height: width * 90 / 180)
                    .offset(x: CGFloat(frame.x) * width / 180)
                    .accessibilityLabel("\(character.name)动作预览")
            } else {
                Image(character.chibiAsset + "Detail").resizable().scaledToFit()
                    .frame(width: width * 72 / 180, height: width * 90 / 180)
            }
            }.frame(width: width, height: width * 96 / 180)
             .clipShape(RoundedRectangle(cornerRadius: 18))
             .contentShape(Rectangle())
             .onTapGesture { greet() }
             .accessibilityElement(children: .ignore)
             .accessibilityIdentifier("motionPreviewStage")
             .accessibilityLabel("\(character.name)动作预览")
             .accessibilityValue(reactionBegan.map { context.date.timeIntervalSince($0) < 1.2 } == true ? "正在打招呼" : reactionBegan != nil ? "已回应招呼" : "正在预览")
             .accessibilityHint("轻点和她打招呼")
             .accessibilityAddTraits(.isButton)
             .accessibilityAction { greet() }
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: action) { _, _ in began = Date(); reactionBegan = nil }
        .onChange(of: settings) { _, _ in began = Date(); reactionBegan = nil }
        .onChange(of: character.id) { _, _ in began = Date(); reactionBegan = nil }
    }
    private func greet() {
        guard !reduceMotion, character.motionProfile?.greetingFrames?.isEmpty == false else { return }
        let now = Date()
        if let start = reactionBegan, now.timeIntervalSince(start) < 1.2 { return }
        reactionX = frame(elapsed: now.timeIntervalSince(began), at: now)?.x ?? 0
        reactionBegan = now
        // Pause the activity playhead during the response so walking resumes
        // from the same position instead of jumping forward after the wave.
        began = began.addingTimeInterval(1.2)
    }
    private func frame(elapsed: TimeInterval, at date: Date) -> MotionFrame? {
        guard !reduceMotion else { return nil }
        if let start = reactionBegan, let frames = character.motionProfile?.greetingFrames, !frames.isEmpty {
            let elapsed = date.timeIntervalSince(start)
            if elapsed >= 0 && elapsed < 1.2 {
                let index = min(frames.count - 1, Int(elapsed / 1.2 * Double(frames.count)))
                return MotionFrame(asset: frames[index],
                    x: reactionX, action: "greeting")
            }
        }
        if action == "random" {
            guard let plan = settings.plan(seed: 0) else { return nil }
            return MotionTimeline.timeline(for: character)?.frame(plan: plan, elapsed: elapsed)
        }
        return MotionTimeline.timeline(for: character)?.preview(action: action, elapsed: elapsed)
    }
}


