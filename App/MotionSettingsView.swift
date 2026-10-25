import SwiftUI

struct MotionSettingsView: View {
    @ObservedObject var store: CompanionStore
    @State private var previewAction = "random"
    var body: some View {
        WorldPage {
            HStack {
                PageHeading(eyebrow: "DAILY LIFE", title: "小白的日常", subtitle: "挑选喜欢的小动作，让她自己玩一会儿。")
                Spacer(minLength: 0)
                AppearanceToggle()
            }
            VStack(spacing: 12) {
                MotionArtworkPreview(settings: store.motionSettings, action: previewAction)
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
            }.worldCard()
            VStack(alignment: .leading, spacing: 17) {
                Toggle("自动活动", isOn: binding(\.automatic))
                    .accessibilityIdentifier("automaticMotionToggle")
                Text("开始陪伴后回到桌面，无需再点动作按钮。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Toggle("走路 · 轻快来回", isOn: binding(\.walk))
                    .accessibilityIdentifier("walkMotionToggle")
                Toggle("打滚 · 蜷身再起身", isOn: binding(\.roll))
                    .accessibilityIdentifier("rollMotionToggle")
                Text("每 5 秒安排一段动作，做完后自然待机。未勾选的动作不会参与随机；都不勾选时只待机。")
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
    @State private var began = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / Double(MotionTimeline.shared?.fps ?? 30), paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(began)
            if let frame = frame(elapsed: elapsed) {
                Image(frame.asset).resizable().scaledToFit()
                    .frame(width: 150, height: 187.5)
                    .offset(x: CGFloat(frame.x) * 200 / 128)
                    .accessibilityLabel("小白动作预览")
            } else {
                Image("XiaobaiChibiDetail").resizable().scaledToFit()
                    .frame(width: 150, height: 187.5)
            }
        }
        .onChange(of: action) { _, _ in began = Date() }
        .onChange(of: settings) { _, _ in began = Date() }
    }
    private func frame(elapsed: TimeInterval) -> MotionFrame? {
        guard !reduceMotion else { return nil }
        if action == "random" {
            guard let plan = settings.plan(seed: 0) else { return nil }
            return MotionTimeline.shared?.frame(plan: plan, elapsed: elapsed)
        }
        guard let durations = MotionTimeline.shared?.durations?[action], !durations.isEmpty else { return nil }
        let period = action == "roll" ? 2000 : durations.reduce(0, +)
        var time = Int(elapsed * 1000) % period
        if action == "roll", time < durations.reduce(0, +) * 2 {
            time %= durations.reduce(0, +)
        }
        var index = durations.count - 1
        for i in durations.indices { if time < durations[i] { index = i; break }; time -= durations[i] }
        return MotionFrame(asset: "Motion_\(action)_\(String(format: "%03d", index))", x: 0, action: action)
    }
}
