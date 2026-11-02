import SpriteKit
import UIKit

/// Atlas pages are shared; all instances of an enemy use the same clip time.
/// Never materialize 240 individual UIImages for each monster.
final class SurvivorTextures {
    private struct Catalog: Decodable { let skills: [PixelFXSkill]; let characters: [SurvivorLocalCharacter]? }
    let media: SurvivorMedia
    let root: URL
    let characters: [SurvivorLocalCharacter]
    let skills: [PixelFXSkill]
    private var clipIndex: [String: SurvivorMedia.Clip] = [:]
    private var resident: [String: SKTexture] = [:]
    // A bounded set of current/next weapon entry pages survives cache eviction.
    // Other animation pages keep using the existing 96MB rolling cache.
    private var upgradePages: [String: SKTexture] = [:]
    private var upgradeFiles = Set<String>()
    let idleImage: UIImage
    let arrowTexture:SKTexture
    let idleTexture: SKTexture
    private let pages = NSCache<NSString, SKTexture>()
    private var current: [String: (Int, SKTexture)] = [:]
    private let previewPages = NSCache<NSString, UIImage>()
    private let thumbnails = NSCache<NSString, UIImage>()
    init() throws {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("SurvivorGameV3"),
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
        let catalog=try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("PixelFXCatalog.json")))
        skills=catalog.skills;characters=catalog.characters ?? []
        guard let idle = UIImage(contentsOfFile: root.appendingPathComponent("dafeiyu-idle.png").path) else { throw CocoaError(.fileReadCorruptFile) }
        idleImage = idle
        idleTexture = SKTexture(image: idle)
        guard let arrow=UIImage(contentsOfFile:root.appendingPathComponent("arrow-pose.png").path) else {throw CocoaError(.fileReadCorruptFile)}
        arrowTexture=SKTexture(image:arrow)
        pages.totalCostLimit = 96 * 1024 * 1024
        pages.countLimit = 64
        previewPages.countLimit = 3; thumbnails.totalCostLimit = 20*1024*1024
    }
    func resolved(_ id:String)->String { skills.first(where:{$0.id==id})?.localLevels?.first?.clipID ?? id }
    func clip(_ id: String) -> SurvivorMedia.Clip? { clipIndex[resolved(id)] }
    private var pending=Set<String>()
    private let decodeQueue = DispatchQueue(label: "maiverse.survivor.atlas-decode", qos: .userInitiated)
    private var stalledFiles = Set<String>()
    private(set) var pageWaits = 0
    private func request(_ file:String) {
        guard !pending.contains(file),pages.object(forKey:file as NSString)==nil,resident[file]==nil,upgradePages[file]==nil else { return }
        pending.insert(file);let root=self.root
        decodeQueue.async {
            let image=UIImage(contentsOfFile:root.appendingPathComponent(file).path)?.preparingForDisplay()
            DispatchQueue.main.async {
                self.pending.remove(file)
                self.stalledFiles.remove(file)
                if let image { let t=SKTexture(image:image);t.filteringMode = .nearest
                    if self.upgradeFiles.contains(file) { self.upgradePages[file] = t }
                    self.pages.setObject(t,forKey:file as NSString,cost:Int(image.size.width*image.size.height*4)) }
            }
        }
    }
    func retireUnused(_ ids:Set<String>) { current=current.filter{ids.contains($0.key)} }
    private func entryFiles(_ ids: [String]) -> Set<String> {
        Set(ids.flatMap { id -> [String] in
            guard let clip = clip(id) else { return [] }
            var files = Array(clip.pages.prefix(1).map(\.file))
            // This confirmed charge module begins at 2.4s, not source frame 0.
            if clip.id == "seeking-swords-lv5", let frame = clip.frame(at: 2.4, looping: false) {
                files.append(clip.pages[frame.cell / (clip.grid[0] * clip.grid[1])].file)
            }
            return files
        })
    }
    func warmUpgrades(_ ids: [String]) {
        upgradeFiles = entryFiles(ids)
        upgradePages = upgradePages.filter { upgradeFiles.contains($0.key) }
        for file in upgradeFiles {
            if let texture = resident[file] ?? pages.object(forKey: file as NSString) {
                upgradePages[file] = texture
            } else { request(file) }
        }
    }
    // Decode off the render thread, then upload before resuming simulation.
    func prepare(_ ids: [String], completion: @escaping (Bool) -> Void) {
        let files = entryFiles(ids)
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
        if let cached = current[clip.id], cached.0 == frame.cell { return cached.1 }
        let capacity = clip.grid[0] * clip.grid[1]
        let pageIndex = frame.cell / capacity
        let file = clip.pages[pageIndex].file
        // Decode two pages ahead, including the wrap of full-length walking
        // clips. The runtime looping argument also covers loop=false sources
        // which the game explicitly repeats without altering their timing.
        if clip.pages.count > 1 {
            for offset in 1...min(2, clip.pages.count - 1) {
                let next = pageIndex + offset
                if next < clip.pages.count || looping {
                    request(clip.pages[next % clip.pages.count].file)
                }
            }
        }
        let page: SKTexture
        if let cached = resident[file] { page = cached }
        else if let cached = upgradePages[file] { page = cached }
        else if let cached = pages.object(forKey: file as NSString) { page = cached }
        else {
            if stalledFiles.insert(file).inserted { pageWaits += 1 }
            request(file); return current[clip.id]?.1
        }

        let cell = frame.cell % capacity
        let w = 1 / CGFloat(clip.grid[0]), h = 1 / CGFloat(clip.grid[1])
        let rect = CGRect(x: CGFloat(cell % clip.grid[0]) * w,
                          y: 1 - CGFloat(cell / clip.grid[0] + 1) * h, width: w, height: h)
        let result = SKTexture(rect: rect, in: page)
        result.filteringMode = id == "dafeiyu-run" || id == "demon-run" || id == "mushroom-run" ? .linear : .nearest
        current[clip.id] = (frame.cell, result)
        return result
    }
    func releaseCache() {
        current.removeAll(); pages.removeAllObjects(); resident.removeAll()
        upgradeFiles.removeAll(); upgradePages.removeAll()
    }
    func resetStatistics() { pageWaits = 0; stalledFiles.removeAll() }
    func thumbnail(_ id: String) -> UIImage? {
        if let image = thumbnails.object(forKey:id as NSString) { return image }
        guard let image = UIImage(contentsOfFile:root.appendingPathComponent("Icons/\(id).png").path) else { return nil }
        thumbnails.setObject(image,forKey:id as NSString,cost:Int(image.size.width*image.size.height*4)); return image
    }
    func preview(_ id: String, time: Double) -> UIImage? {
        guard let clip = media.clips.first(where: { $0.id == resolved(id) }), let frame = clip.frame(at:time,looping:true) else { return nil }
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
    private var arrowNodes: [UInt64: SKSpriteNode] = [:]
    private var feedbackNodes: [UInt64: SKSpriteNode] = [:]
    private var renderStatistics = SurvivorRenderStatistics()
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
        viewpoint.setScale(SurvivorViewport.cameraScale)
        for _ in 0..<49 {
            let tile = SKSpriteNode(texture: floorTexture, size: CGSize(width: tileSize, height: tileSize))
            tile.zPosition = -10000; world.addChild(tile); tiles.append(tile)
        }
        shadow.fillColor = .black.withAlphaComponent(0.24); shadow.strokeColor = .clear
        shadow.zPosition = -500; world.addChild(shadow)
        world.addChild(hero)
        addGrasslandFeatures()
    }
    required init?(coder: NSCoder) { fatalError("Use init(textures:)") }
    func resetTimestamp() { lastTime = nil; renderStatistics.resumeSampling() }
    override func didChangeSize(_ oldSize: CGSize) { resetTimestamp() }
    func resetRun() {
        for dict in [enemyNodes, effectNodes, dropNodes, feedbackNodes,arrowNodes] { for node in dict.values { node.removeFromParent() } }
        enemyNodes = [:]; effectNodes = [:]; dropNodes = [:]; feedbackNodes = [:];arrowNodes=[:]
        lastTime = nil
        renderStatistics = SurvivorRenderStatistics(); textures.resetStatistics()
        lastSimulationTime = game?.battle.clock.elapsed ?? 0; heroAnimationTime = 0
        textures.releaseCache()
        if let battle = game?.battle { render(battle) }
    }
    override func update(_ currentTime: TimeInterval) {
        guard let game else { return }
        let delta = lastTime.map { min(0.05, max(0, currentTime - $0)) } ?? 0
        lastTime = currentTime
        if renderStatistics.record(at: currentTime) {
            game.reportRenderStatistics(renderStatistics, pageWaits: textures.pageWaits)
        }
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
        if Int(time*10)%10==0 {
            let active=Set(battle.enemies.compactMap(\.variant)+(battle.pixelFX?.casts.compactMap(\.clipID) ?? [])+["dafeiyu-run"])
            textures.retireUnused(active)
        }
        let simulatedDelta = max(0, time - lastSimulationTime)
        lastSimulationTime = time
        heroAnimationTime = battle.moving ? heroAnimationTime + simulatedDelta : 0
        let player = point(battle.player)
        let half=CGFloat(SurvivorGrassland.halfSide)
        let cameraCenter = SurvivorViewport.center(player: battle.player, width: Double(size.width), height: Double(size.height))
        viewpoint.position = point(cameraCenter)
        let originX = floor(player.x / tileSize), originY = floor(player.y / tileSize)
        for (index, tile) in tiles.enumerated() {
            tile.position = CGPoint(x: (originX + CGFloat(index % 7 - 3)) * tileSize,
                                    y: (originY + CGFloat(index / 7 - 3)) * tileSize)
        }
        for tile in tiles {
            tile.isHidden=abs(tile.position.x)>half || abs(tile.position.y)>half
            tile.xScale=abs(Int(tile.position.x/tileSize))%2==0 ? 1:-1
            tile.yScale=abs(Int(tile.position.y/tileSize))%2==0 ? 1:-1
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
            guard let clip = enemy.variant, textures.clip(clip) != nil else { continue }
            animate(node, clip: clip, time: enemy.variant?.contains("group01") == true ? time : time-(enemy.born ?? 0), height: enemy.kind == .boss ? 170 : enemy.kind == .elite ? 110 : 72,
                    left: !enemy.facingLeft)
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
        let casts = (battle.pixelFX?.casts ?? []).filter{$0.age>=0}
        prune(&effectNodes,keeping:Set(casts.map(\.id)))
        for effect in casts {
            let node=node(for:effect.id,in:&effectNodes)
            guard let id=effect.clipID,let clip=textures.clip(id) else {continue}
            animate(node,clip:id,time:effect.age+(effect.clipOffset ?? 0),height:CGFloat(clip.cellSize[1]) * CGFloat(clip.displayScale ?? 1),looping:clip.loop ?? false)
            node.xScale=1;node.position=point(effect.position)
            node.zRotation=CGFloat(effect.angle ?? 0)
            node.zPosition=effect.profile == .orbit ? 200:150
        }
        let shots=battle.monsterShots ?? []
        prune(&arrowNodes,keeping:Set(shots.map(\.id)))
        for shot in shots {
            let node=node(for:shot.id,in:&arrowNodes)
            node.texture=textures.arrowTexture;node.size=CGSize(width:56,height:6);node.anchorPoint=CGPoint(x:0.9,y:0.5)
            node.position=point(shot.position);node.zPosition=140;node.zRotation=CGFloat(atan2(shot.velocity.y,shot.velocity.x))
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
    private func addGrasslandFeatures() {
        for points in SurvivorGrassland.paths {
            let path=CGMutablePath();path.move(to:point(points[0]))
            points.dropFirst().forEach{path.addLine(to:point($0))}
            let trail=SKShapeNode(path:path);trail.strokeColor=UIColor(red:0.48,green:0.43,blue:0.29,alpha:0.38);trail.lineWidth=52;trail.lineCap = .round;trail.zPosition = -9990;world.addChild(trail)
        }
        // Finite closed square, shared with physics and minimap. Low stones and
        // dense dark brush at the perimeter; no endless ground recycling outside.
        let edge=CGFloat(SurvivorGrassland.halfSide-48)
        for side in 0..<4 { for i in 0..<160 {
            let t = -edge+CGFloat(i)*edge*2/159
            let node=SKSpriteNode(texture:boundaryTexture)
            node.size=CGSize(width:96,height:112);node.zPosition = -300
            node.position=side==0 ? CGPoint(x:t,y:-edge):side==1 ? CGPoint(x:t,y:edge):side==2 ? CGPoint(x:-edge,y:t):CGPoint(x:edge,y:t)
            node.zRotation=CGFloat(side)*CGFloat.pi/2;world.addChild(node)
        }}
    }
    private lazy var boundaryTexture:SKTexture = {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let image=UIGraphicsImageRenderer(size:CGSize(width:96,height:112),format:format).image { context in
            let c=context.cgContext
            for i in 0..<12 {
                let x=CGFloat(i*29%80),y=CGFloat(i*17%83)
                UIColor(red:0.12,green:0.18,blue:0.12,alpha:1).setFill();c.fillEllipse(in:CGRect(x:x-5,y:y,width:38,height:30))
                UIColor(red:0.29,green:0.30,blue:0.23,alpha:1).setFill();c.fillEllipse(in:CGRect(x:x,y:y+8,width:24,height:20))
                UIColor(red:0.43,green:0.43,blue:0.33,alpha:1).setStroke();c.setLineWidth(2);c.strokeEllipse(in:CGRect(x:x+2,y:y+8,width:20,height:16))
            }
        };return SKTexture(image:image)
    }()
    private func makeFloor() -> SKTexture {
        guard let image=UIImage(contentsOfFile:textures.root.appendingPathComponent("Terrain/grass.png").path) else {return SKTexture(image:UIImage())}
        let texture=SKTexture(image:image);texture.filteringMode = .linear;return texture
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
