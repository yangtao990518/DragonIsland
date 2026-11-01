import SwiftUI

struct SurvivorMinimapView:View {
    let player:SurvivorVector
    let viewport:CGSize
    var body:some View {
        Canvas { context,size in
            let side=SurvivorGrassland.halfSide*2
            func map(_ p:SurvivorVector)->CGPoint {CGPoint(x:(p.x/side+0.5)*size.width,y:(0.5-p.y/side)*size.height)}
            let rect=CGRect(origin:.zero,size:size)
            context.fill(Path(rect),with:.color(Color(red:0.21,green:0.25,blue:0.12)))
            for points in SurvivorGrassland.paths {
                var path=Path();path.move(to:map(points[0]));points.dropFirst().forEach{path.addLine(to:map($0))}
                context.stroke(path,with:.color(.white.opacity(0.25)),lineWidth:1)
            }
            context.stroke(Path(rect.insetBy(dx:2,dy:2)),with:.color(.black.opacity(0.8)),lineWidth:4)
            let p=map(player)
            let w=viewport.width/side*size.width,h=viewport.height/side*size.height
            // Camera clamps at the perimeter, while the cyan dot remains player.
            let cx=max(w/2,min(size.width-w/2,p.x)),cy=max(h/2,min(size.height-h/2,p.y-55/side*size.height))
            context.stroke(Path(CGRect(x:cx-w/2,y:cy-h/2,width:w,height:h)),with:.color(.white),lineWidth:1)
            context.fill(Path(ellipseIn:CGRect(x:p.x-2,y:p.y-2,width:4,height:4)),with:.color(.cyan))
        }.clipShape(RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).stroke(.white.opacity(0.6),lineWidth:1))
            .allowsHitTesting(false).accessibilityElement(children:.ignore)
            .accessibilityLabel("正方形草地小地图").accessibilityValue("青点是人物，白框是当前视野")
    }
}
