import SwiftUI

struct MotionSettingsView: View {
    @ObservedObject var store: CompanionStore
    @State private var previewAction = "random"
    var body: some View {
        WorldPage {
            HStack {
                PageHeading(eyebrow: "DAILY LIFE", title: "\(store.displayCharacter.name)���ճ�", subtitle: "��ѡϲ����С�����������Լ���һ�����")
                Spacer(minLength: 0)
                AppearanceToggle()
            }
            VStack(spacing: 12) {
                MotionArtworkPreview(settings: store.motionSettings, action: previewAction, scene: store.islandScene, character: store.displayCharacter)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                Picker("����Ԥ��", selection: $previewAction) {
                    Text("���").tag("random")
                    Text("����").tag("idle")
                    Text("����").tag("walk_right")
                    Text("����").tag("walk_left")
                    Text("���").tag("roll")
                }.pickerStyle(.segmented)
                Text("����Ԥ��").font(.caption).foregroundStyle(.secondary)
                Text("���С�����������к���")
                    .font(.caption).foregroundStyle(.secondary)
            }.worldCard()
            VStack(alignment: .leading, spacing: 17) {
                Toggle("�Զ��", isOn: binding(\.automatic))
                    .accessibilityIdentifier("automaticMotionToggle")
                Text("��ʼ����ص����棬�����ٵ㶯����ť��")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Toggle("��· �� �ߵ��߱��ٻ���", isOn: binding(\.walk))
                    .accessibilityIdentifier("walkMotionToggle")
                Toggle("��� �� �����߹����ٻ���", isOn: binding(\.roll))
                    .accessibilityIdentifier("rollMotionToggle")
                Text("��·������������Լ 10 ���ߵ���һ�ˣ����۷����������Ҳ�����������ƶ���Լ 5 ��һ������δ��ѡ�Ķ���������룬������ѡʱֻ������")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }.disabled(store.busy).worldCard()
            Text("���ûᱣ�沢Ӧ�õ�ǰ��顣�����ճ�Ƭ��Ϊ 60 ��ѭ����������̬Ч����Ϣ��������ʱ��ʾ��̬���")
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
                    .accessibilityLabel("\(character.name)����Ԥ��")
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
             .accessibilityLabel("\(character.name)����Ԥ��")
             .accessibilityValue(reactionBegan.map { context.date.timeIntervalSince($0) < 1.2 } == true ? "���ڴ��к�" : reactionBegan != nil ? "�ѻ�Ӧ�к�" : "����Ԥ��")
             .accessibilityHint("���������к�")
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


