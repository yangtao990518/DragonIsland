#if DEBUG
import SwiftUI
import SpriteKit

@MainActor private final class SurvivorAssetProof:ObservableObject {
    @Published var scene:SKScene?
    @Published var error:String?
    init() {
        do {
            let textures=try SurvivorTextures()
            textures.prepare(["skeleton-group01-skeleton-roles-R1C1","fireball-flight"]) { ready in
                if ready {self.scene=ProofScene(textures:textures)}
                else {self.error="透明素材预载失败"}
            }
        } catch {self.error=String(describing:error)}
    }
}

private final class ProofScene:SKScene {
    private let textures:SurvivorTextures
    private let actor=SKSpriteNode(),flame=SKSpriteNode()
    private var started:Double?
    init(textures:SurvivorTextures) {
        self.textures=textures
        super.init(size:CGSize(width:640,height:260));scaleMode = .aspectFit
        for row in 0..<13 {for column in 0..<32 {
            let color:UIColor = (row+column)%2==0 ? .init(white:0.75,alpha:1):.init(white:0.35,alpha:1)
            let cell=SKSpriteNode(color:color,size:CGSize(width:20,height:20));cell.position=CGPoint(x:CGFloat(column*20+10),y:CGFloat(row*20+10));addChild(cell)
        }}
        let feet=SKShapeNode(rect:CGRect(x:50,y:54,width:240,height:1));feet.strokeColor = .systemPink;addChild(feet)
        actor.position=CGPoint(x:160,y:54);flame.position=CGPoint(x:500,y:130)
        actor.zPosition=5;flame.zPosition=5;addChild(actor);addChild(flame)
        let marker=SKShapeNode(circleOfRadius:3);marker.position=actor.position;marker.fillColor = .cyan;marker.zPosition=8;addChild(marker)
    }
    required init?(coder:NSCoder){fatalError()}
    override func update(_ time:TimeInterval) {
        if started==nil {started=time};let age=time-(started ?? time)
        for (node,id,loop) in [(actor,"skeleton-group01-skeleton-roles-R1C1",false),(flame,"fireball-flight",true)] {
            guard let clip=textures.clip(id),let texture=textures.texture(id,at:age,looping:loop) else{continue}
            node.texture=texture;node.size=CGSize(width:CGFloat(clip.cellSize[0]),height:CGFloat(clip.cellSize[1]))
            node.anchorPoint=CGPoint(x:clip.pivot[0],y:clip.pivot[1]);node.texture?.filteringMode = .nearest
        }
    }
}

struct SurvivorAssetProofView:View {
    @StateObject private var proof=SurvivorAssetProof()
    var body:some View {
        VStack(spacing:8) {
            Text("原生透明素材检查").font(.headline)
            if let scene=proof.scene {SpriteView(scene:scene,preferredFramesPerSecond:60).accessibilityIdentifier("nativeAssetProofScene")}
            else {ProgressView()}
            HStack {
                Text("锈刃盾卫 · 240帧 · 4.016667秒 · 固定脚底 · 末帧保持")
                Text("火球飞行 · 72帧 · 1.200秒 · 原点110,40")
            }.font(.caption).accessibilityIdentifier("nativeAssetProofTiming")
            if let error=proof.error {Text(error).foregroundStyle(.red)}
        }.padding(12).background(.black).foregroundStyle(.white)
    }
}
#endif
