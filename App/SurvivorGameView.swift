import SwiftUI
import SpriteKit
import UIKit

@MainActor final class SurvivorGameController: ObservableObject {
    @Published private(set) var renderStatistics = SurvivorRenderStatistics()
    private(set) var pageWaits = 0
    func reportRenderStatistics(_ value: SurvivorRenderStatistics, pageWaits: Int) {
        self.pageWaits = pageWaits; renderStatistics = value
    }
    @Published private(set) var preparing = false
    private let audio = SurvivorAudio()
    private let hurtFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var preparationID = UUID()
    private(set) var preparationCount = 0
    private var upgradeWarmIn = 0.0
    private var upcomingClipIDs: [String] {
        SurvivorLocalSkills.warmClipIDs(skills: battle.pixelSkills,
            ranks: Dictionary(uniqueKeysWithValues: battle.pixelSkills.map { ($0.id, battle.rank($0.upgrade)) }))
    }
    private func warmUpcomingUpgrades() { textures?.warmUpgrades(upcomingClipIDs) }
    private func prepareBattle() {
        guard let textures else { return }
        preparationCount += 1
        preparing = true; movement = .zero
        scene?.isPaused=true; scene?.view?.isPaused=true
        let request=UUID(); preparationID=request
        let ids=battle.equippedPixelSkills.compactMap { skill in skill.localLevels?.first(where:{$0.level==battle.rank(skill.upgrade)})?.clipID } + textures.characters.flatMap { ["hd-"+$0.id,"hd-"+$0.id+"-attack"] } + ["hd-dafeiyu-idle","hd-xiaobai-idle","hd-orbit-blade","hd-orbit-crescent","hd-bone-death","hd-bone-arrow","hd-curse-bolt","hd-frost-bolt","hd-healing-pulse","fireball-flight","fireball-impact","lightning-lv1","lightning-explosion","archer-arrow","seeking-flight","seeking-merged"]
        textures.prepare(ids + upcomingClipIDs) { [weak self] ready in
            guard let self, self.preparationID == request else { return }
            self.preparing=false
            if !ready { self.error="战斗图集预载失败，已暂停。请重新进入试炼。"; self.battle.pause(.menu) }
            self.warmUpcomingUpgrades()
            self.syncRenderer(); self.revision += 1
        }
    }
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
    @Published var selectedHeroID = "dafeiyu"
    var heroID: String { playing ? (battle.heroID ?? "dafeiyu") : selectedHeroID }
    var heroName: String { heroID == "xiaobai" ? "小白" : "大肥鱼" }
    var portrait: UIImage? { textures?.heroPortraits[heroID] }
    @Published var starterID = UserDefaults.standard.string(forKey:"survivorPixelStarter") ?? "fireball"
    func icon(for upgrade:SurvivorUpgrade)->UIImage? { thumbnail(upgrade.effectID ?? SurvivorLocalSkills.supportIcons[upgrade] ?? "") }
    var skills: [PixelFXSkill] { textures?.skills ?? [] }
    var starterName: String { skills.first { $0.id == starterID }?.title ?? "火球术" }
    func thumbnail(_ id: String) -> UIImage? { textures?.thumbnail(id) }
    func preview(_ id: String, time: Double) -> UIImage? { textures?.preview(id,time:time) }
    func selectStarter(_ id: String) {
        guard skills.contains(where: { $0.id == id && $0.selectable }) else { return }
        starterID = id; UserDefaults.standard.set(id,forKey:"survivorPixelStarter")
    }
    @discardableResult func chooseSupport(_ upgrade:SurvivorUpgrade)->Bool {
        guard battle.chooseLocalSupport(upgrade) else{return false}
        warmUpcomingUpgrades(); syncRenderer();revision += 1;save();return true
    }
    @discardableResult func chooseLibrarySkill(_ id: String) -> Bool {
        guard battle.choosePixelFXFromLibrary(id) else { return false }
        warmUpcomingUpgrades(); syncRenderer(); revision += 1; save(); return true
    }

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
            do { try previous.configurePixelFX(textures.skills,starter:validStarter) }
            catch { self.error = "无法更新本局技能。"; return }
            previous.resume(.background); previous.resume(.menu); battle = previous
        } else {
            let duration = (textures.clip("thunder-1")?.durationMS ?? 4096.009) / 1000
            do {
                battle = try SurvivorBattle(seed: UInt64.random(in: 1...UInt64.max), thunderDuration: duration)
                try battle.configurePixelFX(textures.skills,starter:validStarter)
            }
            catch { self.error = "无法开始试炼。"; return }
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if !continuing, args.contains("--survivor-upgrade-preview"), args.contains("--maiverse-capture"),
           let index = args.firstIndex(of: "--chat-test-store"), args.indices.contains(index + 1), UUID(uuidString: args[index + 1]) != nil {
            let points = args.contains("--survivor-upgrade-chain-preview") ?
                (0..<4).reduce(0) { $0 + 20 + (battle.level + $1) * 12 } : battle.experienceNeeded
            battle.awardExperience(points)
        }
        #endif
        #if DEBUG
        if args.contains("--survivor-scale-preview"), args.contains("--maiverse-capture") {
            for index in 0..<18 {
                let angle=Double(index)*Double.pi/9
                let kind:SurvivorEnemyKind = index == 0 ? .boss : index % 6 == 0 ? .elite : .demon
                battle.spawnEnemy(at:.init(x:cos(angle)*740,y:sin(angle)*320),kind:kind)
            }
        }
        if args.contains("--survivor-stress-preview"), args.contains("--maiverse-capture") {
            for skill in textures.skills.filter(\.selectable).prefix(6) {
                for _ in battle.rank(skill.upgrade)..<5 {
                    battle.awardExperience(battle.experienceNeeded); _ = battle.choosePixelFXFromLibrary(skill.id)
                }
            }
            for index in 0..<100 {
                let angle=Double(index)*2.399
                battle.spawnEnemy(at:.init(x:cos(angle)*320,y:sin(angle)*320),kind:.demon)
            }
        }
        #endif
        movement = .zero; scene?.resetRun(); renderStatistics = SurvivorRenderStatistics(); pageWaits = 0
        preparationCount = 0; upgradeWarmIn = 0
        if !continuing { battle.heroID = selectedHeroID }
        battle.configureHD2D(textures.monsterRules)
        playing = true; audio.reset(); prepareBattle(); revision += 1
        save()
    }
    private var validStarter: String { skills.contains { $0.id == starterID && $0.selectable } ? starterID : skills.first(where: { $0.id == "fireball" && $0.selectable })?.id ?? skills.first(where: \.selectable)?.id ?? "fireball" }
    func tick(_ delta: Double) {
        guard playing, !preparing, battle.clock.running, battle.outcome == nil,
              let scene, scene.size.width > scene.size.height else { return }
        battle.setViewport(width: Double(scene.size.width), height: Double(scene.size.height))
        let oldCast=battle.pixelFX?.casts.filter{$0.age>=0}.map(\.id).max() ?? 0
        let oldHealth=battle.health
        let oldHit=battle.combatHits?.last?.id ?? 0
        let oldChoices = battle.choices, oldOutcome = battle.outcome
        do { try battle.advance(by: delta, movement: movement) }
        catch { self.error = "战斗状态异常，已暂停。"; battle.pause(.menu) }
        if battle.health < oldHealth {
            hurtFeedback.impactOccurred(intensity: 0.8)
            audio.play("hit",time:battle.clock.elapsed)
        }
        else if oldChoices != battle.choices { audio.play("upgrade",time:battle.clock.elapsed) }
        else if battle.health > oldHealth { audio.play("heal",time:battle.clock.elapsed) }
        else if (battle.combatHits?.last?.id ?? 0) > oldHit { audio.play("hit",time:battle.clock.elapsed) }
        else if (battle.pixelFX?.casts.filter{$0.age>=0}.map(\.id).max() ?? 0)>oldCast { audio.play(battle.pixelFX?.casts.last(where:{$0.age>=0})?.skillID ?? "cast",time:battle.clock.elapsed) }
        audio.update(running:battle.clock.running && battle.outcome == nil)
        upgradeWarmIn -= delta
        if upgradeWarmIn <= 0 || oldChoices != battle.choices {
            upgradeWarmIn = 1; warmUpcomingUpgrades()
        }
        publishIn -= delta
        if publishIn <= 0 || oldChoices != battle.choices || oldOutcome != battle.outcome {
            publishIn = 0.1; revision += 1
        }
        if oldChoices != battle.choices || oldOutcome != battle.outcome { movement = .zero; save() }
    }
    func choose(_ upgrade: SurvivorUpgrade) {
        if battle.choose(upgrade) {
            warmUpcomingUpgrades(); syncRenderer(); revision += 1; save()
        }
    }
    func pause(_ reason: SurvivorRunClock.PauseReason) {
        movement = .zero; battle.pause(reason); syncRenderer(); revision += 1
        if playing { save() }
    }
    func resume(_ reason: SurvivorRunClock.PauseReason) {
        movement = .zero; battle.resume(reason); syncRenderer(); revision += 1
    }
    private func syncRenderer() {
        scene?.resetTimestamp()
        let paused = preparing || !battle.clock.running || battle.outcome != nil
        // A scene first attached while an upgrade is open must also resume its
        // existing SKView; do not rely only on SpriteView's initial parameter.
        audio.update(running:playing && !paused)
        scene?.isPaused = paused
        scene?.view?.isPaused = paused
    }
    func lobby() {
        if battle.outcome == nil { pause(.menu) }
        preparing=false; preparationID=UUID(); audio.stop()
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
    enum LibraryMode: String, Identifiable { case starter, upgrade; var id: String { rawValue } }
    @StateObject private var game = SurvivorGameController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @AppStorage("survivorMusicMuted") private var musicMuted=false
    @AppStorage("survivorEffectsMuted") private var effectsMuted=false
    @State private var confirmExit = false
    @State private var libraryMode: LibraryMode?
    @State private var mapZoom = 1.0
    private let ink = Color(red: 0.07, green: 0.12, blue: 0.22)

    var body: some View {
        ZStack {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--survivor-asset-smoke") {SurvivorAssetProofView()}
            else { gameContent }
            #else
            gameContent
            #endif
        }
        .onAppear { GameOrientationDelegate.setGame(game.playing || isAssetProof) }
        .onChange(of: game.playing) { _, playing in GameOrientationDelegate.setGame(playing) }
        .onDisappear { if game.playing {game.pause(.background)};GameOrientationDelegate.setGame(false) }
    }
    private var isAssetProof: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--survivor-asset-smoke")
        #else
        false
        #endif
    }
    private var gameContent:some View {
        ZStack {
            if game.playing, let scene = game.scene {
                SpriteView(scene: scene, isPaused: game.preparing || !game.battle.clock.running || game.battle.outcome != nil,
                           preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea().accessibilityLabel("灵境试炼战场")
                    .accessibilityIdentifier("survivorBattleScene")
                    .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--maiverse-capture") ? "资源准备次数：\(game.preparationCount)" : "自动战斗")
                battleOverlay
            } else { lobby }
            if game.preparing { ZStack { Color.black.opacity(0.7).ignoresSafeArea(); ProgressView("正在准备战斗素材…").padding(24).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20)) }.accessibilityIdentifier("survivorLoading") }
        }
        .preferredColorScheme(.dark)
        .sheet(item:$libraryMode) { mode in PixelFXLibraryView(game:game,upgrading:mode == .upgrade) }
        .onChange(of: phase) { _, value in
            if value == .active { game.resume(.background) }
            else { game.pause(.background) }
        }
        .confirmationDialog("离开试炼？当前进度会保存在本机，可以稍后继续。", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("保存并返回选角") { game.lobby() }.accessibilityIdentifier("survivorSaveExit")
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
                            Text("鲸潮生存战").font(.caption2.monospaced()).tracking(3).foregroundStyle(.cyan.opacity(0.8))
                        }
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.white.opacity(0.1), in: Circle()) }.accessibilityLabel("关闭游戏")
                    }
                    HStack { Label("选择出战角色", systemImage: "person.crop.circle"); Spacer(); Text(game.heroID == "xiaobai" ? "02 / 02":"01 / 02").monospacedDigit().foregroundStyle(.secondary) }.font(.subheadline)
                    HStack {
                        ForEach(["dafeiyu","xiaobai"], id: \.self) { id in
                            Button(id == "dafeiyu" ? "大肥鱼":"小白") {game.selectedHeroID=id}
                                .buttonStyle(.bordered).tint(game.selectedHeroID == id ? .cyan:.gray)
                                .accessibilityIdentifier("survivorHero_"+id)
                        }
                    }
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: [.indigo.opacity(0.5), .cyan.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Circle().stroke(.cyan.opacity(0.25), lineWidth: 1).frame(width: 220, height: 220).offset(x: 100, y: -40)
                        Image(uiImage: game.portrait ?? UIImage()).resizable().scaledToFit().frame(height: 260).frame(maxWidth: .infinity).padding(.bottom, 58)
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(game.heroName).font(.title2.bold())
                                Text("鲸潮使者 · \(game.starterName)").font(.caption).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.cyan)
                        }.padding(22)
                    }.frame(height: 340).overlay(RoundedRectangle(cornerRadius: 28).stroke(.cyan.opacity(0.5)))
                    HStack(spacing: 10) {
                        lobbyTag("20分钟", icon: "timer")
                        lobbyTag("自动攻击", icon: "drop.fill")
                        lobbyTag("升级三选一", icon: "sparkles")
                    }
                    Button { libraryMode = .starter } label: {
                        HStack {
                            Image(systemName:"square.grid.2x2.fill")
                            VStack(alignment:.leading,spacing:5) {
                                Text("技能与特性").font(.headline)
                                Text("\(game.skills.filter(\.selectable).count)项战斗技能 · 初始技能：\(game.starterName)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName:"chevron.right")
                        }.padding(18).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:20))
                    }.buttonStyle(.plain).accessibilityIdentifier("survivorSkillLibrary")
                    VStack(alignment: .leading, spacing: 12) {
                        Label("本次试炼", systemImage: "map").font(.headline)
                        Text("拖动摇杆走位，拾取灵晶升级。技能全部自动释放，升级时可强化或从 技能库挑选新技能。每局最多装备6项，每项最高5级。")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineSpacing(5)
                        Text("升级、暂停及切到后台时，战斗与计时一起暂停。")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
                    if let error = game.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if game.canContinue {
                        actionButton("继续上次试炼", icon: "play.fill") { game.start(continuing: true) }
                            .accessibilityIdentifier("survivorContinue")
                    }
                    actionButton(game.canContinue ? "重新开始" : "开始试炼", icon: "sparkles") { game.start() }
                        .accessibilityIdentifier("survivorStart")
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
                    VStack(alignment:.trailing,spacing:6) {
                        HStack(spacing:5) {
                            ForEach(game.battle.equippedPixelSkills) { skill in
                                VStack(spacing:2) {
                                    if let image=game.thumbnail(skill.id) {Image(uiImage:image).resizable().scaledToFit().frame(width:36,height:36)}
                                    Text("\(game.battle.rank(skill.upgrade))级").font(.system(size:9).bold())
                                }.accessibilityIdentifier("survivorSkillRank_\(skill.id)")
                            }
                        }
                        HStack(spacing:5) {
                            ForEach([SurvivorUpgrade.stride,.haste,.power,.vitality,.defense]) { upgrade in
                                if game.battle.rank(upgrade)>0,let image=game.icon(for:upgrade) {
                                    Image(uiImage:image).resizable().scaledToFit().frame(width:24,height:24).overlay(alignment:.bottomTrailing){Text("\(game.battle.rank(upgrade))").font(.system(size:8).bold())}
                                }
                            }
                        }
                        Text("自动释放").font(.caption2).foregroundStyle(.white.opacity(0.65))
                    }.padding(10).background(.black.opacity(0.3),in:RoundedRectangle(cornerRadius:14))
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
                Image(uiImage: game.portrait ?? UIImage()).resizable().scaledToFit().frame(width: 34, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(game.heroName) · Lv.\(game.battle.level)").font(.caption.bold())
                    ProgressView(value: game.battle.health, total: game.battle.maximumHealth).tint(.mint).frame(width: 98)
                    Text("\(Int(game.battle.health)) / \(Int(game.battle.maximumHealth))").font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 6)
                VStack(spacing: 3) {
                    Text(timer(game.battle.clock.remaining)).font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
                        .accessibilityIdentifier("survivorTimer")
                        .accessibilityValue(game.battle.clock.running ? "运行中" : "暂停中")
                    Text("击败 \(game.battle.kills)").font(.caption2).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 6)
                Button { game.pause(.menu) } label: {
                    Image(systemName: "pause.fill").frame(width: 42, height: 42).background(.white.opacity(0.12), in: Circle())
                }.accessibilityLabel("暂停与地图").accessibilityIdentifier("survivorPause")
            }
            ProgressView(value: Double(min(game.battle.experience, game.battle.experienceNeeded)), total: Double(game.battle.experienceNeeded)).tint(.cyan)
        }.padding(10).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 14).padding(.top, 6)
    }
    private var upgrades: some View {
        modal {
            Text("灵力突破").font(.system(size: 29, weight: .bold, design: .serif))
            Text("选择一项强化 · 战斗已暂停").font(.subheadline).foregroundStyle(.white.opacity(0.6))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),alignment:.leading,spacing:12) {
            ForEach(game.battle.choices) { upgrade in
                Button { game.choose(upgrade) } label: {
                    VStack(alignment:.leading,spacing:12) {
                        Group {
                            if let image=game.icon(for:upgrade) { Image(uiImage:image).resizable().interpolation(.none).scaledToFit() }
                            else { Image(systemName:upgrade.symbol).font(.title2).foregroundStyle(.cyan) }
                        }.frame(width:64,height:64).padding(4).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:14))
                        VStack(alignment: .leading, spacing: 7) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(game.battle.title(for:upgrade)).font(.headline)
                                Text(game.battle.rank(upgrade) == 0 ? "新技能" : "Lv.\(game.battle.rank(upgrade)) → \(game.battle.rank(upgrade) + 1)")
                                    .font(.caption).foregroundStyle(.cyan)
                            }
                            Text(game.battle.detail(for:upgrade)).font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.leading)
                        }
                    }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.14)))
                }.buttonStyle(.plain).accessibilityIdentifier("survivorUpgrade_\(upgrade.rawValue)")
            }
            }
            Button { libraryMode = .upgrade } label: { Label("从技能库选择",systemImage:"square.grid.2x2") }
                .accessibilityIdentifier("survivorUpgradeLibrary")
        }
    }
    private var pauseMenu: some View {
        modal {
            Text("暂停 · 地图").font(.title2.bold())
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 8) {
                    SurvivorMinimapView(player: game.battle.player,
                        viewport: game.scene?.size ?? CGSize(width: 844, height: 390),
                        drops: game.battle.drops, zoom: mapZoom)
                        .frame(width: pauseMapSize, height: pauseMapSize)
                    HStack {
                        ForEach([1.0, 2.0, 4.0], id: \.self) { zoom in
                            Button("\(Int(zoom))×") { mapZoom = zoom }
                                .tint(mapZoom == zoom ? .cyan : .gray)
                        }
                    }.buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("计时、怪物和技能均已暂停").font(.caption).foregroundStyle(.secondary)
                    Text("金点：人物  白框：视野  蓝点：经验").font(.caption2).foregroundStyle(.secondary)
                    if let error = game.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    Text("渲染 \(renderFPS) · 已装备\(game.battle.equippedPixelSkills.count)项技能").font(.caption)
                    Text(String(format: "慢帧 %d · 最长 %.1f ms · 图集等候 %d", game.renderStatistics.slowFrames, game.renderStatistics.longestFrameMS, game.pageWaits))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityIdentifier("survivorRenderDiagnostics")
                    HStack(spacing: 18) {
                        Toggle("音乐",isOn:Binding(get:{!musicMuted},set:{musicMuted = !$0}))
                        Toggle("音效",isOn:Binding(get:{!effectsMuted},set:{effectsMuted = !$0}))
                    }
                    actionButton("继续试炼", icon: "play.fill") { game.resume(.menu) }
                        .accessibilityIdentifier("survivorResume")
                    Button("保存并返回选角") { confirmExit = true }.font(.subheadline).padding(6).accessibilityIdentifier("survivorReturnLobby")
                }
            }
        }
    }
    private var renderFPS: String {
        let fps = game.renderStatistics.framesPerSecond
        return fps > 0 ? "\(fps) FPS" : "采样中"
    }
    private var pauseMapSize: CGFloat { (game.scene?.size.height ?? 390) < 360 ? 148 : 184 }
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
                VStack(spacing: 18, content: content).padding(20).frame(maxWidth: 760)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("移动摇杆").accessibilityIdentifier("survivorJoystick")
    }
}
