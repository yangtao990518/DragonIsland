import SwiftUI

struct MotionSettingsView: View {
    @ObservedObject var store: CompanionStore
    let character: CompanionCharacter
    @State private var previewAction = "random"
    private var settings: MotionSettings { store.settings(for: character) }
    var body: some View {
        WorldPage {
            PageHeading(eyebrow: "DAILY LIFE", title: "\(character.name)的日常", subtitle: "分别挑选她喜欢的动作，设置会单独保存。")
            VStack(spacing: 12) {
                if previewAction == "pet_walk_video" {
                    DogWalkVideoPreview()
                        .frame(height: 220)
                } else {
                    MotionArtworkPreview(settings: settings, action: previewAction, scene: store.islandScene, character: character)
                        .frame(height: 220).frame(maxWidth: .infinity)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 10) {
                    previewButton("随机", id: "random")
                    previewButton("待机", id: "idle")
                    previewButton("右走", id: "walk_right")
                    previewButton("左走", id: "walk_left")
                    previewButton("打滚", id: "roll")
                    ForEach(character.motionProfile?.dailyActions ?? []) { item in
                        previewButton(item.title, id: item.id)
                    }
                }
                if character.id == "dafeiyu" {
                    previewButton("遛狗(视频测试版)", id: "pet_walk_video")
                    Text("视频测试版仅在 App 内播放，与遛狗抽帧版使用同一份已确认动画、同样速度和尺寸。为方便直接比较，两者都在黑色背景上显示。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(previewAction == "pet_walk_video" ? "视频预览 · 不参与岛上自动动作" : "动作预览 · 轻点小人物和她打招呼")
                    .font(.caption).foregroundStyle(.secondary)
            }.worldCard()
            VStack(alignment: .leading, spacing: 17) {
                Toggle("自动活动", isOn: binding(\.automatic))
                    .accessibilityIdentifier("automaticMotionToggle")
                Text("开始陪伴后按下方勾选的动作自动活动。关闭自动活动时显示静态人物。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("走路 · 走到边边再回来", isOn: binding(\.walk))
                    .accessibilityIdentifier("walkMotionToggle")
                Toggle("打滚 · 向两边滚，再回来", isOn: binding(\.roll))
                    .accessibilityIdentifier("rollMotionToggle")
                ForEach(character.motionProfile?.dailyActions ?? []) { item in
                    Toggle(item.title + " · 来回活动", isOn: binding(item.id == "ride" ? \.ride : \.petWalk))
                        .accessibilityIdentifier("dailyMotionToggle_\(item.id)")
                }
                Text("每个动作独立开关，关闭走路不会关闭御剑、骑鲸或遛狗。全部关闭时只待机；每轮会安排所有已选动作。走动约 7～10 秒一个方向，打滚约 5 秒一个方向。")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            }.disabled(store.busy).worldCard()
            Text("设置仅应用于\(character.name)；她正在陪伴时立即生效。减弱动态效果或息屏低亮度时，岛上显示静态人物。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func previewButton(_ title: String, id: String) -> some View {
        Button(title) { previewAction = id }
            .buttonStyle(.bordered)
            .tint(previewAction == id ? AppPalette.accent : .secondary)
            .accessibilityIdentifier("dailyMotion_\(id)")
            .accessibilityAddTraits(previewAction == id ? .isSelected : [])
    }
    private func binding(_ key: WritableKeyPath<MotionSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: key] }, set: { value in
            var updated = settings
            updated[keyPath: key] = value
            Task { await store.setMotionSettings(updated, for: character) }
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
          TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(began)
            ZStack {
              Image((character.id == "dafeiyu" && action == "pet_walk" ? IslandScene.black : scene).asset).resizable()
            if let frame = frame(elapsed: elapsed, at: context.date) {
                Image(frame.asset).resizable().scaledToFit()
                    .frame(width: width * CGFloat(frame.width ?? 72) / 180, height: width * CGFloat(frame.height ?? 90) / 180)
                    .offset(y: width * CGFloat(90 - (frame.height ?? 90)) / 360)
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
            guard let plan = settings.plan(seed: 0, character: character) else { return nil }
            return MotionTimeline.timeline(for: character)?.frame(plan: plan, elapsed: elapsed)
        }
        return MotionTimeline.timeline(for: character)?.preview(action: action, elapsed: elapsed)
    }
}


