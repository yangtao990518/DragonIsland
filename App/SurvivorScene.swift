import SpriteKit
import UIKit

/// Atlas pages are shared; all instances of an enemy use the same clip time.
/// Never materialize 240 individual UIImages for each monster.
final class SurvivorTextures {
    private struct Catalog: Decodable { let skills: [PixelFXSkill] }
    let media: SurvivorMedia
    let root: URL
    let skills: [PixelFXSkill]
    private var clipIndex: [String: SurvivorMedia.Clip] = [:]
    private var resident: [String: SKTexture] = [:]
    let idleImage: UIImage
    let idleTexture: SKTexture
    private let pages = NSCache<NSString, SKTexture>()
    private var current: [String: (Int, SKTexture)] = [:]
    private let previewPages = NSCache<NSString, UIImage>()
    private let thumbnails = NSCache<NSString, UIImage>()
    init() throws {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("SurvivorGameV2"),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.root = root
        let decoded = try JSONDecoder().decode(SurvivorMedia.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        try decoded.validate()
        media = decoded
        let combat = try JSONDecoder().decode(SurvivorMedia.self,from:Data(contentsOf:root.appendingPathComponent("combat.json")))
        try combat.validate()
        clipIndex = Dictionary(uniqueKeysWithValues:decoded.clips.map { ($0.id,$0) })
        for clip in combat.clips { clipIndex[clip.id] = clip }
        skills = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("PixelFXCatalog.json"))).skills
        guard let idle = UIImage(contentsOfFile: root.appendingPathComponent("dafeiyu-idle.png").path) else { throw CocoaError(.fileReadCorruptFile) }
        idleImage = idle
        idleTexture = SKTexture(image: idle)
        pages.totalCostLimit = 64 * 1024 * 1024
        pages.countLimit = 12
        previewPages.countLimit = 3; thumbnails.totalCostLimit = 20*1024*1024
    }
    func clip(_ id: String) -> SurvivorMedia.Clip? { clipIndex[id] }
    // Decode off the render thread, then upload before resuming simulation.
    func prepare(_ ids: [String], completion: @escaping (Bool) -> Void) {
        let files = Set(ids.flatMap { clip($0)?.pages.map(\.file) ?? [] })
        let root = self.root
        DispatchQueue.global(qos:.userInitiated).async {
            let images = files.compactMap { file -> (String,UIImage)? in
                guard let image = UIImage(contentsOfFile:root.appendingPathComponent(file).path)?.preparingForDisplay() else { return nil }
                return (file,image)
            }
            DispatchQueue.main.async {
                guard images.count == files.count else { completion(false); return }
                self.current.removeAll(); self.resident.removeAll()
                for (file,image) in images {
                    let texture = SKTexture(image:image); texture.filteringMode = file.contains("dafeiyu") || file.contains("demon") || file.contains("mushroom") ? .linear : .nearest
                    self.resident[file] = texture
                }
                SKTexture.preload(Array(self.resident.values)) { DispatchQueue.main.async { completion(true) } }
            }
        }
    }
    func texture(_ id: String, at seconds: Double, looping: Bool = true) -> SKTexture? {
        guard let clip = clip(id), let frame = clip.frame(at: seconds, looping: looping) else { return nil }
        if let cached = current[id], cached.0 == frame.cell { return cached.1 }
        let capacity = clip.grid[0] * clip.grid[1]
        let pageIndex = frame.cell / capacity
        let file = clip.pages[pageIndex].file
        let page: SKTexture
        if let cached = resident[file] { page = cached }
        else if let cached = pages.object(forKey: file as NSString) { page = cached }
        else {
            if file.hasPrefix("Combat/") { return nil }
            guard let image = UIImage(contentsOfFile: root.appendingPathComponent(file).path) else { return nil }
            page = SKTexture(image: image); page.filteringMode = file.hasPrefix("PixelFX/") ? .nearest : .linear
            pages.setObject(page, forKey: file as NSString, cost: Int(image.size.width * image.size.height * 4))
        }
        let cell = frame.cell % capacity
        let w = 1 / CGFloat(clip.grid[0]), h = 1 / CGFloat(clip.grid[1])
        let rect = CGRect(x: CGFloat(cell % clip.grid[0]) * w,
                          y: 1 - CGFloat(cell / clip.grid[0] + 1) * h, width: w, height: h)
        let result = SKTexture(rect: rect, in: page)
        result.filteringMode = file.hasPrefix("PixelFX/") ? .nearest : .linear
        current[id] = (frame.cell, result)
        return result
    }
    func releaseCache() { current.removeAll(); pages.removeAllObjects(); resident.removeAll() }
    func thumbnail(_ id: String) -> UIImage? {
        if let image = thumbnails.object(forKey:id as NSString) { return image }
        guard let image = UIImage(contentsOfFile:root.appendingPathComponent("PixelFX/Thumbnails/\(id).png").path) else { return nil }
        thumbnails.setObject(image,forKey:id as NSString,cost:Int(image.size.width*image.size.height*4)); return image
    }
    func preview(_ id: String, time: Double) -> UIImage? {
        guard let clip = media.clips.first(where: { $0.id == id }), let frame = clip.frame(at:time,looping:true) else { return nil }
        let capacity = clip.grid[0]*clip.grid[1], cell = frame.cell%capacity, path = clip.pages[frame.cell/capacity].file
        let image: UIImage
        if let cached = previewPages.object(forKey:path as NSString) { image = cached }
        else {
            guard let loaded = UIImage(contentsOfFile:root.appendingPathComponent(path).path) else { return nil }
            image = loaded; previewPages.setObject(loaded,forKey:path as NSString)
        }
        let w = clip.cellSize[0], h = clip.cellSize[1]
        guard let crop = image.cgImage?.cropping(to:CGRect(x:cell%clip.grid[0]*w,y:cell/clip.grid[0]*h,width:w,height:h)) else { return nil }
        return UIImage(cgImage:crop)
    }
}

final class SurvivorScene: SKScene {
    weak var game: SurvivorGameController?
    private let textures: SurvivorTextures
    private let world = SKNode()
    private let viewpoint = SKCameraNode()
    private let hero = SKSpriteNode()
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 36, height: 12))
    private var idle: SKTexture { textures.idleTexture }
    private var enemyNodes: [UInt64: SKSpriteNode] = [:]
    private var effectNodes: [UInt64: SKSpriteNode] = [:]
    private var dropNodes: [UInt64: SKSpriteNode] = [:]
    private var feedbackNodes: [UInt64: SKSpriteNode] = [:]
    private var fpsTime: TimeInterval?
    private var frameCount=0
    private var lastTime: TimeInterval?
    private var lastSimulationTime = 0.0
    private var heroAnimationTime = 0.0
    private var tiles: [SKSpriteNode] = []
    private let tileSize: CGFloat = 480
    private lazy var floorTexture = makeFloor()
    private lazy var experienceTexture = makeExperience()

    init(textures: SurvivorTextures) {
        self.textures = textures
        super.init(size: CGSize(width: 844, height: 390))
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.08, green: 0.14, blue: 0.19, alpha: 1)
        addChild(world); addChild(viewpoint); camera = viewpoint
        viewpoint.setScale(1.0)
        for _ in 0..<49 {
            let tile = SKSpriteNode(texture: floorTexture, size: CGSize(width: tileSize, height: tileSize))
            tile.zPosition = -10000; world.addChild(tile); tiles.append(tile)
        }
        shadow.fillColor = .black.withAlphaComponent(0.24); shadow.strokeColor = .clear
        shadow.zPosition = -500; world.addChild(shadow)
        world.addChild(hero)
    }
    required init?(coder: NSCoder) { fatalError("Use init(textures:)") }
    func resetTimestamp() { lastTime = nil; fpsTime=nil; frameCount=0 }
    func resetRun() {
        for dict in [enemyNodes, effectNodes, dropNodes, feedbackNodes] { for node in dict.values { node.removeFromParent() } }
        enemyNodes = [:]; effectNodes = [:]; dropNodes = [:]; feedbackNodes = [:]
        lastTime = nil
        lastSimulationTime = game?.battle.clock.elapsed ?? 0; heroAnimationTime = 0
        textures.releaseCache()
        if let battle = game?.battle { render(battle) }
    }
    override func update(_ currentTime: TimeInterval) {
        guard let game else { return }
        let delta = lastTime.map { min(0.05, max(0, currentTime - $0)) } ?? 0
        lastTime = currentTime
        frameCount += 1
        if let start=fpsTime, currentTime-start>=1 {
            game.reportFrameRate(Int(Double(frameCount)/(currentTime-start))); frameCount=0; fpsTime=currentTime
        } else if fpsTime == nil { fpsTime=currentTime }
        game.tick(delta)
        render(game.battle)
    }
    private func point(_ vector: SurvivorVector) -> CGPoint { CGPoint(x: vector.x, y: vector.y) }
    private func animate(_ node: SKSpriteNode, clip id: String, time: Double, height: CGFloat,
                         left: Bool = true, looping: Bool = true) {
        guard let clip = textures.clip(id), let texture = textures.texture(id, at: time, looping: looping) else { return }
        node.texture = texture
        node.size = CGSize(width: height * CGFloat(clip.cellSize[0]) / CGFloat(clip.cellSize[1]), height: height)
        node.anchorPoint = CGPoint(x: clip.pivot[0], y: clip.pivot[1])
        node.xScale = left ? 1 : -1
    }
    private func render(_ battle: SurvivorBattle) {
        let time = battle.clock.elapsed
        let simulatedDelta = max(0, time - lastSimulationTime)
        lastSimulationTime = time
        heroAnimationTime = battle.moving ? heroAnimationTime + simulatedDelta : 0
        let player = point(battle.player)
        viewpoint.position = CGPoint(x: player.x, y: player.y + 55)
        let originX = floor(player.x / tileSize), originY = floor(player.y / tileSize)
        for (index, tile) in tiles.enumerated() {
            tile.position = CGPoint(x: (originX + CGFloat(index % 7 - 3)) * tileSize,
                                    y: (originY + CGFloat(index / 7 - 3)) * tileSize)
        }
        shadow.position = player
        if hero.childNode(withName:"marker") == nil {
            let marker = SKShapeNode(ellipseOf:CGSize(width:58,height:20)); marker.name="marker"
            marker.strokeColor = .cyan; marker.lineWidth=2; marker.glowWidth=2; marker.fillColor = .cyan.withAlphaComponent(0.12)
            marker.zPosition = -1; hero.addChild(marker)
        }
        hero.position = player; hero.zPosition = 500
        if battle.moving { animate(hero, clip: "dafeiyu-run", time: heroAnimationTime, height: 100, left: battle.facingLeft) }
        else {
            hero.texture = idle; hero.size = CGSize(width: 100 * idle.size().width / max(1, idle.size().height), height: 100)
            hero.anchorPoint = CGPoint(x: 0.5, y: 0.04); hero.xScale = 1
        }
        hero.alpha = battle.playerIsInvincible && Int(time * 12) % 2 == 0 ? 0.65 : 1
        prune(&enemyNodes, keeping: Set(battle.enemies.map(\.id)))
        for enemy in battle.enemies {
            let node = node(for: enemy.id, in: &enemyNodes)
            let clip = enemy.kind == .mushroom ? "mushroom-run" : "demon-run"
            animate(node, clip: clip, time: time, height: enemy.kind == .boss ? 122 : enemy.kind == .elite ? 76 : 55,
                    left: enemy.facingLeft)
            node.position = point(enemy.position); node.zPosition = 90 - node.position.y * 0.01
            node.color = .white; node.colorBlendFactor = time < enemy.hitUntil ? 0.65 : 0
            if enemy.kind == .boss {
                let bar: SKShapeNode
                if let existing = node.childNode(withName: "health") as? SKShapeNode { bar = existing }
                else { bar = SKShapeNode(); bar.name = "health"; bar.fillColor = .systemRed; bar.strokeColor = .clear; node.addChild(bar) }
                bar.path = CGPath(rect: CGRect(x: -30, y: 128, width: 60 * max(0, enemy.health / enemy.maximumHealth), height: 5), transform: nil)
            }
        }
        prune(&dropNodes, keeping: Set(battle.drops.map(\.id)))
        for drop in battle.drops {
            let node = node(for: drop.id, in: &dropNodes)
            node.texture = experienceTexture; node.position = point(drop.position)
            node.size = CGSize(width: 10, height: 13); node.zPosition = -200
        }
        let casts = battle.pixelFX?.casts ?? []
        prune(&effectNodes, keeping: Set(casts.map(\.id)))
        for effect in casts {
            let node = node(for: effect.id, in: &effectNodes)
            guard textures.clip(effect.skillID) != nil else { continue }
            let radius = CGFloat(effect.radius)
            let height = effect.profile == .projectile ? radius*3 : effect.profile == .heal ? 100 : max(radius*2,80)
            animate(node,clip:effect.skillID,time:effect.age,height:height,looping:false)
            node.anchorPoint = effect.profile == .projectile ? CGPoint(x:0.5,y:0.5) : CGPoint(x:0.5,y:0.15)
            node.position = point(effect.position)
            if effect.profile == .projectile { node.zRotation = CGFloat(atan2(effect.velocity.y,effect.velocity.x)) }
            node.zPosition = 150
            if effect.profile != .heal {
                let boundary: SKShapeNode
                if let old = node.childNode(withName:"hitArea") as? SKShapeNode { boundary=old }
                else { boundary=SKShapeNode(); boundary.name="hitArea"; node.addChild(boundary) }
                if boundary.path == nil { boundary.path=CGPath(ellipseIn:CGRect(x:-radius,y:-radius,width:radius*2,height:radius*2),transform:nil) }
                boundary.lineWidth=1; boundary.strokeColor = .cyan.withAlphaComponent(0.65)
                boundary.fillColor = .cyan.withAlphaComponent(effect.age < effect.nextPulse && effect.age < 0.65 ? 0.06:0.14)
                boundary.zPosition = -1
            }
        }
        let feedback = (battle.pixelFX?.feedback ?? []).filter { event in time-event.born < (textures.clip(event.skillID)?.durationMS ?? 0)/1000 }
        prune(&feedbackNodes,keeping:Set(feedback.map(\.id)))
        for event in feedback {
            let node = node(for:event.id,in:&feedbackNodes)
            let height = min(220,Double(textures.clip(event.skillID)?.cellSize[1] ?? 100)*1.7)
            animate(node,clip:event.skillID,time:time-event.born,height:CGFloat(height),looping:false)
            node.position = point(event.position); node.zPosition = 160
        }
    }
    private func node(for id: UInt64, in nodes: inout [UInt64: SKSpriteNode]) -> SKSpriteNode {
        if let node = nodes[id] { return node }
        let node = SKSpriteNode(); world.addChild(node); nodes[id] = node; return node
    }
    private func prune(_ nodes: inout [UInt64: SKSpriteNode], keeping ids: Set<UInt64>) {
        for id in Array(nodes.keys) where !ids.contains(id) { nodes.removeValue(forKey: id)?.removeFromParent() }
    }
    private func makeFloor() -> SKTexture {
        let image = UIGraphicsImageRenderer(size: CGSize(width: tileSize, height: tileSize)).image { context in
            let c = context.cgContext
            UIColor(red: 0.11, green: 0.19, blue: 0.23, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
            // Quiet moonlit meadow: seamless path strips and deterministic grass.
            UIColor(red:0.10,green:0.22,blue:0.24,alpha:1).setFill()
            c.fill(CGRect(x:0,y:0,width:tileSize,height:tileSize))
            // Curved garden trail wraps seamlessly across tile edges.
            let path=CGMutablePath()
            for x in stride(from:0,through:480,by:4) {
                let point=CGPoint(x:CGFloat(x),y:240+sin(CGFloat(x)/480*2*CGFloat.pi)*32)
                if x==0 { path.move(to:point) } else { path.addLine(to:point) }
            }
            c.addPath(path); c.setStrokeColor(UIColor(red:0.12,green:0.25,blue:0.26,alpha:1).cgColor); c.setLineWidth(66); c.strokePath()
            c.addPath(path); c.setStrokeColor(UIColor(red:0.24,green:0.33,blue:0.32,alpha:1).cgColor); c.setLineWidth(46); c.strokePath()
            // Shallow moon pools, rock edges and lily pads; baked once.
            for ring in stride(from:8,through:0,by:-1) {
                let r=CGFloat(ring)
                UIColor(red:0.07+Double(ring)*0.009,green:0.20+Double(ring)*0.007,blue:0.29+Double(ring)*0.006,alpha:1).setFill()
                c.fillEllipse(in:CGRect(x:60-r*2,y:63-r,width:100+r*4,height:66+r*2))
            }
            for i in 0..<12 {
                let a=CGFloat(i)*CGFloat.pi/6
                let rect=CGRect(x:105+cos(a)*64,y:90+sin(a)*47,width:10+CGFloat(i%3)*4,height:7)
                UIColor(red:0.30,green:0.39,blue:0.40,alpha:1).setFill(); c.fillEllipse(in:rect)
            }
            UIColor(red:0.19,green:0.42,blue:0.35,alpha:1).setFill()
            c.fillEllipse(in:CGRect(x:86,y:81,width:22,height:11)); c.fillEllipse(in:CGRect(x:123,y:103,width:15,height:9))
            for i in 0..<420 {
                let x=CGFloat((i*83+17)%480), y=CGFloat((i*137+11)%480)
                if abs(y-(240+sin(x/480*2*CGFloat.pi)*32))<36 || (x<185 && y<160) { continue }
                UIColor(red:0.17,green:0.32+Double(i%5)*0.02,blue:0.31,alpha:0.8).setStroke()
                c.setLineWidth(1); c.move(to:CGPoint(x:x,y:y)); c.addLine(to:CGPoint(x:x-2,y:y-4)); c.move(to:CGPoint(x:x,y:y)); c.addLine(to:CGPoint(x:x+3,y:y-6)); c.strokePath()
                if i%29==0 {
                    UIColor(red:0.63,green:0.66,blue:0.85,alpha:0.8).setFill()
                    c.fillEllipse(in:CGRect(x:x,y:y,width:4,height:4))
                }
            }
            for i in 0..<8 {
                let x=CGFloat(230+(i*71)%210), y=CGFloat(40+(i*53)%100)
                UIColor(red:0.07,green:0.17,blue:0.19,alpha:0.7).setFill(); c.fillEllipse(in:CGRect(x:x-5,y:y+5,width:39,height:20))
                UIColor(red:0.17,green:0.33,blue:0.28,alpha:1).setFill(); c.fillEllipse(in:CGRect(x:x,y:y,width:30,height:24))
                UIColor(red:0.24,green:0.40,blue:0.33,alpha:1).setFill(); c.fillEllipse(in:CGRect(x:x+4,y:y,width:20,height:13))
            }
        }
        return SKTexture(image: image)
    }
    private func makeExperience() -> SKTexture {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 20)).image { context in
            let c = context.cgContext
            c.move(to: CGPoint(x: 8, y: 1)); c.addLine(to: CGPoint(x: 15, y: 10))
            c.addLine(to: CGPoint(x: 8, y: 19)); c.addLine(to: CGPoint(x: 1, y: 10)); c.closePath()
            UIColor(red: 0.45, green: 0.8, blue: 1, alpha: 1).setFill(); c.fillPath()
        }
        return SKTexture(image: image)
    }
}
