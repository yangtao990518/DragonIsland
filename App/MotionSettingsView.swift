import SwiftUI

struct MotionSettingsView: View {
    @ObservedObject var store: CompanionStore
    let character: CompanionCharacter
    @State private var previewAction = "idle"
    private var settings: MotionSettings { store.settings(for: character) }
    private var previewTitle: String {
        switch previewAction {
        case "random": return "随机"
        case "idle": return "待机"
        case "walk_left": return "左走"
        case "walk_right": return "右走"
        case "roll": return "打滚"
        default: return character.motionProfile?.dailyActions?.first { $0.id == previewAction }?.title ?? "待机"
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(MoonPalette.gold)
                    Text(character.name).font(.system(size: 16, weight: .medium, design: .serif))
                    Image(systemName: "sparkle").foregroundStyle(MoonPalette.gold)
                }.padding(.top, 8)
                previewStage
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        previewButton("随机", id: "random")
                        previewButton("待机", id: "idle")
                        previewButton("左走", id: "walk_left")
                        previewButton("右走", id: "walk_right")
                        previewButton("打滚", id: "roll")
                        ForEach(character.motionProfile?.dailyActions ?? []) { item in previewButton(item.title, id: item.id) }
                    }.padding(2)
                }
                MoonCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: binding(\.automatic)) {
                            Label("岛上自动活动", systemImage: "sparkles")
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                        }.accessibilityIdentifier("automaticMotionToggle")
                        Text("下方开关决定灵动岛自动活动。上方只在 App 内预览，不会改变开关。")
                            .font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6)).lineSpacing(4)
                    }
                }.disabled(store.busy)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    actionCard("走路", subtitle: "走到边边，再回来", symbol: "figure.walk", enabled: binding(\.walk), id: "walkMotionToggle", action: "walk_right")
                    actionCard("打滚", subtitle: "向两边打滚", symbol: "arrow.2.circlepath", enabled: binding(\.roll), id: "rollMotionToggle", action: "roll")
                    ForEach(character.motionProfile?.dailyActions ?? []) { item in
                        actionCard(item.title, subtitle: item.id.hasPrefix("dance") ? "原时长完整播放" : "她的专属日常",
                                   symbol: item.id.hasPrefix("dance") ? "music.note" : item.id == "pet_walk" ? "pawprint.fill" : "sparkles",
                                   enabled: actionBinding(item.id), id: "dailyMotionToggle_\(item.id)", action: item.id)
                    }
                }.disabled(store.busy)
                Text("每个角色独立保存。关闭全部动作时保留待机；舞蹈完整播放，已确认的两分钟排程保持不变。")
                    .font(.caption).foregroundStyle(MoonPalette.ink.opacity(0.6)).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                Text("她正在陪伴时设置立即生效。减弱动态效果或息屏低亮度时，岛上显示静态人物。")
                    .font(.caption2).foregroundStyle(MoonPalette.ink.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(18).padding(.bottom, 18)
        }
        .background { MoonBackdrop().ignoresSafeArea() }
        .foregroundStyle(MoonPalette.ink).tint(MoonPalette.violet)
        .toolbarBackground(MoonPalette.paper, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
    }
    private var previewStage: some View {
        ZStack(alignment: .bottom) {
            MoonBackdrop(night: true)
            Group {
                if previewAction == "dance1" || previewAction == "dance2" {
                    FullVideoActionPreview(characterID: character.id, action: previewAction)
                        .id("\(character.id)-\(previewAction)").padding(.horizontal, 12).padding(.bottom, 30)
                } else {
                    MotionArtworkPreview(settings: settings, action: previewAction, scene: store.islandScene, character: character)
                        .padding(.horizontal, 8).padding(.bottom, 25)
                }
            }.frame(height: 236)
            Text("✦  当前：\(previewTitle)  ✦")
                .font(.system(size: 11, weight: .medium, design: .serif)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 6)
                .background(MoonPalette.violet.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(MoonPalette.gold.opacity(0.8), lineWidth: 1))
                .padding(.bottom, 9).accessibilityIdentifier("motionCurrentAction")
        }.frame(height: 236).clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(alignment: .topTrailing) {
                Label("App 内预览", systemImage: "play.fill").font(.system(size: 9))
                    .foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule()).padding(12)
            }
            .overlay(RoundedRectangle(cornerRadius: 26).inset(by: 3).stroke(MoonPalette.gold.opacity(0.8), lineWidth: 1))
    }
    private func actionCard(_ title: String, subtitle: String, symbol: String, enabled: Binding<Bool>, id: String, action: String) -> some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(MoonPalette.violet)
                    Spacer(minLength: 3)
                    Toggle(title, isOn: enabled).labelsHidden().accessibilityLabel(title + "岛上自动活动").accessibilityIdentifier(id)
                }
                Text(title).font(.system(size: 18, weight: .semibold, design: .serif))
                Text(subtitle).font(.caption2).foregroundStyle(MoonPalette.ink.opacity(0.55))
                Button { previewAction = action } label: {
                    Label("预览动作", systemImage: "play.fill").font(.caption)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(MoonPalette.lavender.opacity(0.18), in: Capsule())
                }.buttonStyle(.plain).foregroundStyle(MoonPalette.violet)
            }
        }
    }
    private func previewButton(_ title: String, id: String) -> some View {
        Button { previewAction = id } label: {
            Text(title).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundStyle(previewAction == id ? .white : MoonPalette.violet)
                .background(previewAction == id ? MoonPalette.violet : .white.opacity(0.8), in: Capsule())
                .overlay(Capsule().stroke(MoonPalette.gold.opacity(0.3), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("dailyMotion_\(id)")
            .accessibilityAddTraits(previewAction == id ? .isSelected : [])
    }
    private func actionBinding(_ id: String) -> Binding<Bool> {
        switch id {
        case "ride": return binding(\.ride)
        case "pet_walk": return binding(\.petWalk)
        case "dance1": return binding(\.dance1)
        case "dance2": return binding(\.dance2)
        default: return .constant(false)
        }
    }
    private func binding(_ key: WritableKeyPath<MotionSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: key] }, set: { value in
            var updated = settings; updated[keyPath: key] = value
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
                previewImage(frame).resizable().scaledToFit()
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
    private func previewImage(_ frame: MotionFrame) -> Image {
        if let action = frame.videoAction, let index = frame.sourceFrame,
           let clip = VideoActionFrames.clips.first(where: { $0.characterID == character.id && $0.action == action }),
           let image = VideoActionFrames.image(clip, index: index) { return Image(uiImage: image) }
        return Image(frame.asset)
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


