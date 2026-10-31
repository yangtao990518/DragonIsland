import SwiftUI
import SpriteKit

@MainActor final class SurvivorGameController: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var playing = false
    @Published private(set) var error: String?
    private(set) var battle: SurvivorBattle
    private(set) var scene: SurvivorScene?
    private var textures: SurvivorTextures?
    var movement = SurvivorVector.zero
    private var publishIn = 0.0
    private var suspended: SurvivorBattle?
    private let saveURL: URL?
    var canContinue: Bool { suspended != nil }

    init() {
        battle = try! SurvivorBattle() // The built-in validated configuration.
        saveURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SurvivorGame/run.json")
        if let url = saveURL, let data = try? Data(contentsOf: url),
           let previous = try? JSONDecoder().decode(SurvivorBattle.self, from: data), previous.outcome == nil {
            suspended = previous
        }
        do {
            let textures = try SurvivorTextures()
            self.textures = textures
            let scene = SurvivorScene(textures: textures)
            self.scene = scene; scene.game = self
        } catch { self.error = "游戏素材未能读取，请检查安装包是否包含完整游戏图集。" }
    }
    func start(continuing: Bool = false) {
        guard let textures else { return }
        if continuing, var previous = suspended {
            previous.resume(.background); previous.resume(.menu); battle = previous
        } else {
            let duration = (textures.clip("thunder-1")?.durationMS ?? 4096.009) / 1000
            do { battle = try SurvivorBattle(seed: UInt64.random(in: 1...UInt64.max), thunderDuration: duration) }
            catch { self.error = "无法开始试炼。"; return }
        }
        movement = .zero; scene?.resetRun(); playing = true; revision += 1
        save()
    }
    func tick(_ delta: Double) {
        guard playing, battle.clock.running, battle.outcome == nil else { return }
        let oldChoices = battle.choices, oldOutcome = battle.outcome
        do { try battle.advance(by: delta, movement: movement) }
        catch { error = "战斗状态异常，已暂停。"; battle.pause(.menu) }
        publishIn -= delta
        if publishIn <= 0 || oldChoices != battle.choices || oldOutcome != battle.outcome {
            publishIn = 0.1; revision += 1
        }
        if oldChoices != battle.choices || oldOutcome != battle.outcome { movement = .zero; save() }
    }
    func choose(_ upgrade: SurvivorUpgrade) {
        if battle.choose(upgrade) { scene?.resetTimestamp(); revision += 1; save() }
    }
    func pause(_ reason: SurvivorRunClock.PauseReason) {
        movement = .zero; battle.pause(reason); scene?.resetTimestamp(); revision += 1
        if playing { save() }
    }
    func resume(_ reason: SurvivorRunClock.PauseReason) {
        movement = .zero; battle.resume(reason); scene?.resetTimestamp(); revision += 1
    }
    func lobby() {
        if battle.outcome == nil { pause(.menu) }
        playing = false; scene?.resetTimestamp(); textures?.releaseCache(); revision += 1
    }
    func save() {
        guard let url = saveURL else { return }
        if battle.outcome != nil {
            suspended = nil
            try? FileManager.default.removeItem(at: url)
            return
        }
        suspended = battle
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(battle).write(to: url, options: .atomic)
        } catch { self.error = "本局进度暂时无法保存，请保持 App 运行。" }
    }
}

struct SurvivorGameEntry: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 27)).foregroundStyle(.cyan)
                    .frame(width: 54, height: 54).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 5) {
                    Text("灵境试炼").font(.headline)
                    Text("大肥鱼出战 · 20分钟生存肉鸽").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.bold())
            }
            .foregroundStyle(.white).padding(18)
            .background(LinearGradient(colors: [Color(red: 0.12, green: 0.19, blue: 0.3), Color(red: 0.21, green: 0.19, blue: 0.38)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain).accessibilityIdentifier("openSurvivorGame")
    }
}

struct SurvivorGameView: View {
    @StateObject private var game = SurvivorGameController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var confirmExit = false
    private let ink = Color(red: 0.07, green: 0.12, blue: 0.22)

    var body: some View {
        ZStack {
            if game.playing, let scene = game.scene {
                SpriteView(scene: scene, isPaused: !game.battle.clock.running || game.battle.outcome != nil,
                           preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea().accessibilityLabel("灵境试炼战场")
                battleOverlay
            } else { lobby }
        }
        .preferredColorScheme(.dark)
        .onChange(of: phase) { _, value in
            if value == .active { game.resume(.background) }
            else { game.pause(.background) }
        }
        .onDisappear { if game.playing { game.pause(.background) } }
        .confirmationDialog("离开试炼？当前进度会保存在本机，可以稍后继续。", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("保存并返回选角") { game.lobby() }
            Button("继续战斗", role: .cancel) { }
        }
    }

    private var lobby: some View {
        ZStack {
            LinearGradient(colors: [ink, Color(red: 0.16, green: 0.17, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("灵境试炼").font(.system(size: 30, weight: .bold, design: .serif))
                            Text("SURVIVE THE TIDE").font(.caption2.monospaced()).tracking(3).foregroundStyle(.cyan.opacity(0.8))
                        }
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.white.opacity(0.1), in: Circle()) }.accessibilityLabel("关闭游戏")
                    }
                    HStack { Label("选择出战角色", systemImage: "person.crop.circle"); Spacer(); Text("01 / 01").monospacedDigit().foregroundStyle(.secondary) }.font(.subheadline)
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: [.indigo.opacity(0.5), .cyan.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Circle().stroke(.cyan.opacity(0.25), lineWidth: 1).frame(width: 220, height: 220).offset(x: 100, y: -40)
                        Image("DafeiyuChibiDetail").resizable().scaledToFit().frame(height: 260).frame(maxWidth: .infinity).padding(.bottom, 58)
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("大肥鱼").font(.title2.bold())
                                Text("鲸潮使者 · 初始武器：小水泡").font(.caption).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.cyan)
                        }.padding(22)
                    }.frame(height: 340).overlay(RoundedRectangle(cornerRadius: 28).stroke(.cyan.opacity(0.5)))
                    HStack(spacing: 10) {
                        lobbyTag("20分钟", icon: "timer")
                        lobbyTag("自动攻击", icon: "bubbles.and.sparkles.fill")
                        lobbyTag("升级三选一", icon: "sparkles")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("本次试炼", systemImage: "map").font(.headline)
                        Text("拖动左下摇杆走位，拾取灵晶升级。小水泡自动追击附近敌人；学习紫霄雷后，雷阵自动释放，最高五级。")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineSpacing(5)
                        Text("升级、暂停及切到后台时，战斗与计时一起暂停。")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
                    if let error = game.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if game.canContinue {
                        actionButton("继续上次试炼", icon: "play.fill") { game.start(continuing: true) }
                    }
                    actionButton(game.canContinue ? "重新开始" : "开始试炼", icon: "sparkles") { game.start() }
                        .disabled(game.scene == nil)
                }.padding(24)
            }
        }.foregroundStyle(.white)
    }
    private func lobbyTag(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }
    private var battleOverlay: some View {
        ZStack {
            VStack {
                hud
                Spacer()
                HStack(alignment: .bottom) {
                    SurvivorJoystick(enabled: game.battle.clock.running && game.battle.outcome == nil) { game.movement = $0 }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Label("水泡 \(game.battle.rank(.bubble))", systemImage: "bubbles.and.sparkles.fill")
                        if game.battle.rank(.thunder) > 0 { Label("紫霄雷 \(game.battle.rank(.thunder))", systemImage: "bolt.fill") }
                        Text("自动释放").font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }.font(.caption.bold()).padding(14).background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            if let outcome = game.battle.outcome { result(outcome) }
            else if game.battle.clock.pauseReasons.contains(.menu) { pauseMenu }
            else if !game.battle.choices.isEmpty { upgrades }
            else if game.battle.clock.pauseReasons.contains(.background) {
                Text("已暂停").font(.title2.bold()).padding(24).background(.ultraThinMaterial, in: Capsule())
            }
        }.foregroundStyle(.white)
    }
    private var hud: some View {
        VStack(spacing: 10) {
            HStack {
                Image("DafeiyuChibiDetail").resizable().scaledToFit().frame(width: 34, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("大肥鱼 · Lv.\(game.battle.level)").font(.caption.bold())
                    ProgressView(value: game.battle.health, total: game.battle.maximumHealth).tint(.mint).frame(width: 98)
                    Text("\(Int(game.battle.health)) / \(Int(game.battle.maximumHealth))").font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 6)
                VStack(spacing: 3) {
                    Text(timer(game.battle.clock.remaining)).font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("击败 \(game.battle.kills)").font(.caption2).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 6)
                Button { game.pause(.menu) } label: {
                    Image(systemName: "pause.fill").frame(width: 42, height: 42).background(.white.opacity(0.12), in: Circle())
                }.accessibilityLabel("暂停试炼")
            }
            ProgressView(value: Double(min(game.battle.experience, game.battle.experienceNeeded)), total: Double(game.battle.experienceNeeded)).tint(.cyan)
        }.padding(16).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 14).padding(.top, 6)
    }
    private var upgrades: some View {
        modal {
            Text("灵力突破").font(.system(size: 29, weight: .bold, design: .serif))
            Text("选择一项强化 · 战斗已暂停").font(.subheadline).foregroundStyle(.white.opacity(0.6))
            ForEach(game.battle.choices) { upgrade in
                Button { game.choose(upgrade) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: upgrade.symbol).font(.title2).foregroundStyle(upgrade == .thunder ? .purple : .cyan)
                            .frame(width: 48, height: 56).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(upgrade.title).font(.headline)
                                Spacer()
                                Text(game.battle.rank(upgrade) == 0 ? "新技能" : "Lv.\(game.battle.rank(upgrade)) → \(game.battle.rank(upgrade) + 1)")
                                    .font(.caption).foregroundStyle(.cyan)
                            }
                            Text(upgrade.detail(current: game.battle.rank(upgrade))).font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.leading)
                        }
                    }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.14)))
                }.buttonStyle(.plain).accessibilityIdentifier("survivorUpgrade_\(upgrade.rawValue)")
            }
        }
    }
    private var pauseMenu: some View {
        modal {
            Image(systemName: "moon.stars").font(.largeTitle).foregroundStyle(.cyan)
            Text("稍作休息").font(.title.bold())
            Text("计时、怪物和技能均已暂停").font(.subheadline).foregroundStyle(.secondary)
            if let error = game.error { Text(error).font(.caption).foregroundStyle(.orange) }
            actionButton("继续试炼", icon: "play.fill") { game.resume(.menu) }
            Button("保存并返回选角") { confirmExit = true }.font(.subheadline).padding(10)
        }
    }
    private func result(_ outcome: SurvivorOutcome) -> some View {
        modal {
            Image(systemName: outcome == .victory ? "crown.fill" : "leaf.fill").font(.system(size: 48)).foregroundStyle(outcome == .victory ? .yellow : .cyan)
            Text(outcome == .victory ? "试炼完成" : "下次再战").font(.largeTitle.bold())
            Text("\(timer(game.battle.clock.elapsed)) · 击败\(game.battle.kills) · 等级\(game.battle.level)").font(.subheadline).foregroundStyle(.secondary)
            actionButton("再来一局", icon: "arrow.clockwise") { game.start() }
            Button("返回选角") { game.lobby() }.padding(10)
        }
    }
    private func modal<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18, content: content).padding(24).frame(maxWidth: 460)
                    .background(ink.opacity(0.98), in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.15)))
                    .padding(20).frame(maxWidth: .infinity)
            }.defaultScrollAnchor(.center)
        }
    }
    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
    private func timer(_ seconds: Double) -> String {
        let value = Int(ceil(max(0, seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct SurvivorJoystick: View {
    let enabled: Bool
    let move: (SurvivorVector) -> Void
    @State private var displacement = CGSize.zero
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.07)).overlay(Circle().stroke(.white.opacity(0.18)))
            Image(systemName: "plus").font(.title).foregroundStyle(.white.opacity(0.12))
            Circle().fill(.white.opacity(0.28)).frame(width: 50, height: 50).overlay(Circle().stroke(.white.opacity(0.35)))
                .offset(displacement)
        }.frame(width: 126, height: 126).contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard enabled else { return }
                let x = gesture.location.x - 63, y = gesture.location.y - 63
                let length = max(1, hypot(x, y)), scale = min(44, length) / length
                displacement = CGSize(width: x * scale, height: y * scale)
                move(.init(x: Double(displacement.width / 44), y: -Double(displacement.height / 44)))
            }.onEnded { _ in displacement = .zero; move(.zero) })
            .onChange(of: enabled) { _, value in if !value { displacement = .zero; move(.zero) } }
            .accessibilityLabel("移动摇杆")
    }
}
