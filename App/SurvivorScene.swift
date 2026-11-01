import SpriteKit
import UIKit

/// Atlas pages are shared; all instances of an enemy use the same clip time.
/// Never materialize 240 individual UIImages for each monster.
final class SurvivorTextures {
    private struct Catalog: Decodable { let skills: [PixelFXSkill] }
    let media: SurvivorMedia
    let root: URL
    let skills: [PixelFXSkill]
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
        skills = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("PixelFXCatalog.json"))).skills
        guard let idle = UIImage(contentsOfFile: root.appendingPathComponent("dafeiyu-idle.png").path) else { throw CocoaError(.fileReadCorruptFile) }
        idleImage = idle
        idleTexture = SKTexture(image: idle)
        pages.totalCostLimit = 64 * 1024 * 1024
        pages.countLimit = 12
        previewPages.countLimit = 3; thumbnails.totalCostLimit = 20*1024*1024
    }
    func clip(_ id: String) -> SurvivorMedia.Clip? { media.clips.first { $0.id == id } }
    func texture(_ id: String, at seconds: Double, looping: Bool = true) -> SKTexture? {
        guard let clip = clip(id), let frame = clip.frame(at: seconds, looping: looping) else { return nil }
        if let cached = current[id], cached.0 == frame.cell { return cached.1 }
        let capacity = clip.grid[0] * clip.grid[1]
        let pageIndex = frame.cell / capacity
        let file = clip.pages[pageIndex].file
        let page: SKTexture
        if let cached = pages.object(forKey: file as NSString) { page = cached }
        else {
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
    func releaseCache() { current.removeAll(); pages.removeAllObjects() }
    func thumbnail(_ id: String) -> UIImage? {
        if let image = thumbnails.object(forKey:id as NSString) { return image }
        guard let image = UIImage(contentsOfFile:root.appendingPathComponent("PixelFX/Thumbnails/\(id).png").path) else { return nil }
        thumbnails.setObject(image,forKey:id as NSString,cost:Int(image.size.width*image.size.height*4)); return image
    }
    func preview(_ id: String, time: Double) -> UIImage? {
        guard let clip = clip(id), let frame = clip.frame(at:time,looping:true) else { return nil }
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
    private var lastTime: TimeInterval?
    private var lastSimulationTime = 0.0
    private var heroAnimationTime = 0.0
    private var tiles: [SKSpriteNode] = []
    private let tileSize: CGFloat = 240
    private lazy var floorTexture = makeFloor()
    private lazy var experienceTexture = makeExperience()

    init(textures: SurvivorTextures) {
        self.textures = textures
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.08, green: 0.14, blue: 0.19, alpha: 1)
        addChild(world); addChild(viewpoint); camera = viewpoint
        viewpoint.setScale(1.15)
        for _ in 0..<49 {
            let tile = SKSpriteNode(texture: floorTexture, size: CGSize(width: tileSize, height: tileSize))
            tile.zPosition = -10000; world.addChild(tile); tiles.append(tile)
        }
        shadow.fillColor = .black.withAlphaComponent(0.24); shadow.strokeColor = .clear
        shadow.zPosition = -500; world.addChild(shadow)
        world.addChild(hero)
    }
    required init?(coder: NSCoder) { fatalError("Use init(textures:)") }
    func resetTimestamp() { lastTime = nil }
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
        hero.position = player; hero.zPosition = 100 - player.y * 0.01
        if battle.moving { animate(hero, clip: "dafeiyu-run", time: heroAnimationTime, height: 78, left: battle.facingLeft) }
        else {
            hero.texture = idle; hero.size = CGSize(width: 78 * idle.size().width / max(1, idle.size().height), height: 78)
            hero.anchorPoint = CGPoint(x: 0.5, y: 0.04); hero.xScale = 1
        }
        hero.alpha = battle.playerIsInvincible && Int(time * 12) % 2 == 0 ? 0.4 : 1
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
            guard let clip = textures.clip(effect.skillID) else { continue }
            let cap = effect.profile == .projectile ? 112.0 : effect.profile == .orbit ? 130 : 320
            let height = min(cap,Double(clip.cellSize[1])*1.8)*(1+Double(effect.level-1)*0.07)
            animate(node,clip:effect.skillID,time:effect.age,height:CGFloat(height),looping:textures.skills.first { $0.id == effect.skillID }?.loop ?? false)
            node.position = point(effect.position)
            if effect.profile == .projectile { node.position.y += 22; node.zRotation = CGFloat(atan2(effect.velocity.y,effect.velocity.x)) }
            node.zPosition = effect.profile == .aura ? 70 : 180
        }
        let feedback = (battle.pixelFX?.feedback ?? []).filter { event in time-event.born < (textures.clip(event.skillID)?.durationMS ?? 0)/1000 }
        prune(&feedbackNodes,keeping:Set(feedback.map(\.id)))
        for event in feedback {
            let node = node(for:event.id,in:&feedbackNodes)
            let height = min(220,Double(textures.clip(event.skillID)?.cellSize[1] ?? 100)*1.7)
            animate(node,clip:event.skillID,time:time-event.born,height:CGFloat(height),looping:false)
            node.position = point(event.position); node.zPosition = 200
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
            // Repeating worn stone, generated once; no animated background.
            for row in 0..<4 { for column in 0..<4 {
                let x = CGFloat(column) * 60 + CGFloat(row % 2) * 15 - 8
                let y = CGFloat(row) * 60 + 3
                let rect = CGRect(x: x, y: y, width: 53, height: 54)
                UIColor(red: 0.16, green: 0.26, blue: 0.29, alpha: 0.45).setStroke()
                c.setLineWidth(1); c.stroke(rect.insetBy(dx: 2, dy: 3))
                UIColor(red: 0.26, green: 0.4, blue: 0.35, alpha: 0.35).setFill()
                c.fillEllipse(in: CGRect(x: x + 9, y: y + 39, width: 12, height: 3))
            } }
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
