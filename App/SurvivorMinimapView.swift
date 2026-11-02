import SwiftUI

/// Pause-menu stage map using actual battle positions and existing pickups.
struct SurvivorMinimapView: View {
    let player: SurvivorVector
    let viewport: CGSize
    var drops: [SurvivorExperience] = []
    var zoom = 1.0

    var body: some View {
        Canvas { context, size in
            let projection = SurvivorMapProjection(player: player, zoom: zoom)
            func map(_ p: SurvivorVector) -> CGPoint {
                let n = projection.normalized(p)
                return CGPoint(x: n.x * size.width, y: n.y * size.height)
            }
            let rect = CGRect(origin: .zero, size: size)
            context.clip(to: Path(rect))
            context.fill(Path(rect), with: .color(Color(red: 0.16, green: 0.20, blue: 0.12)))
            for points in SurvivorGrassland.paths {
                var path = Path(); path.move(to: map(points[0]))
                points.dropFirst().forEach { path.addLine(to: map($0)) }
                context.stroke(path, with: .color(.white.opacity(0.2)), lineWidth: 2)
            }
            let half = SurvivorGrassland.halfSide
            let topLeft = map(.init(x: -half, y: half))
            let bottomRight = map(.init(x: half, y: -half))
            context.stroke(Path(CGRect(x: topLeft.x, y: topLeft.y,
                width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)),
                with: .color(.white.opacity(0.5)), lineWidth: 3)
            for drop in drops {
                let p = map(drop.position)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)), with: .color(.cyan))
            }
            let visible = SurvivorViewport.size(width: Double(viewport.width), height: Double(viewport.height))
            let center = SurvivorViewport.center(player: player, width: Double(viewport.width), height: Double(viewport.height))
            let cameraTop = map(center + .init(x: -visible.x / 2, y: visible.y / 2))
            context.stroke(Path(CGRect(x: cameraTop.x, y: cameraTop.y,
                width: visible.x / projection.side * size.width,
                height: visible.y / projection.side * size.height)), with: .color(.white), lineWidth: 1)
            let p = map(player)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.yellow))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.4), lineWidth: 1))
        .allowsHitTesting(false).accessibilityElement(children: .ignore)
        .accessibilityLabel("试炼地图").accessibilityValue("金点是人物，白框是实际视野，蓝点是未拾取经验")
        .accessibilityIdentifier("survivorPauseMap")
    }
}
