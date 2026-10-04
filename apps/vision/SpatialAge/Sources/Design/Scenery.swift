import RealityKit
import simd
import UIKit

/// Per-game backdrops from the Games Ideas deck. Each sits inside the ink stage and covers it while the game runs.
/// Nothing in a backdrop moves, so motion in view is still always a game signal. Unlit, like the stage.
@MainActor
enum Scenery {
    /// Forest clearing: pale sky, grass floor, a ring of trees from 5 to 14 m. Stick Drop and Spatial Tracking.
    /// The layout is fixed (seeded), so every session sees the same trees.
    static func forest(rig: Rig) -> Entity {
        let root = Entity()
        root.name = "forest"
        root.position = rig.origin
        root.orientation = rig.rotation
        if let dome = Meshes.invertedSphere(radius: 30) {
            root.addChild(ModelEntity(mesh: dome, materials: [Look.flat(Theme.sky)]))
        }
        let ground = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 29), materials: [Look.flat(Theme.grass)])
        ground.position.y = 0.004
        root.addChild(ground)

        var rng = SeededRNG(seed: 4021)
        for i in 0..<34 {
            // Two rings: near trees at 5-8 m, a darker far ring at 10-14 m. Jittered so it reads as a wood.
            let far = i >= 16
            let n = far ? 18 : 16, k = far ? i - 16 : i
            let a = (Float(k) + Float.random(in: -0.3...0.3, using: &rng)) / Float(n) * 2 * .pi
            let r = far ? Float.random(in: 10...14, using: &rng) : Float.random(in: 5...8, using: &rng)
            root.addChild(tree(height: Float.random(in: far ? 5...8 : 4...6.5, using: &rng),
                               canopy: far ? Theme.canopyFar : Theme.canopy, rng: &rng,
                               at: [sin(a) * r, 0, -cos(a) * r]))
        }
        return root
    }

    /// Island and moat for Hole in the Wall: a stone platform under the participant, water to 2.6 m, grass beyond.
    static func moat(rig: Rig) -> Entity {
        let root = forest(rig: rig)
        root.name = "moat"
        if let water = Meshes.annulus(inner: islandRadius, outer: 2.6) {
            let e = ModelEntity(mesh: water, materials: [Look.flat(Theme.water)])
            e.position.y = 0.008
            root.addChild(e)
        }
        let island = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: islandRadius),
                                 materials: [Look.flat(Theme.stone)])
        island.position.y = 0.008
        root.addChild(island)
        if let rim = Meshes.ring(radius: islandRadius, thickness: 0.012, segments: 96, sides: 6) {
            let e = ModelEntity(mesh: rim, materials: [Look.flat(Theme.paper.withAlphaComponent(0.6))])
            e.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            e.position.y = 0.012
            root.addChild(e)
        }
        return root
    }

    /// Island radius, meters. Hole in the Wall flags a trial where the head leaves it.
    static let islandRadius: Float = 0.6

    /// Trunk and two or three canopy spheres, standing on the floor at `p` (parent-local).
    private static func tree(height: Float, canopy: UIColor, rng: inout SeededRNG, at p: SIMD3<Float>) -> Entity {
        let t = Entity()
        t.position = p
        let trunkH = height * 0.55
        let trunk = ModelEntity(mesh: .generateCylinder(height: trunkH, radius: Float.random(in: 0.12...0.22, using: &rng)),
                                materials: [Look.flat(Theme.bark)])
        trunk.position.y = trunkH / 2
        t.addChild(trunk)
        for j in 0..<Int.random(in: 2...3, using: &rng) {
            let r = height * Float.random(in: 0.18...0.26, using: &rng)
            let blob = ModelEntity(mesh: .generateSphere(radius: r), materials: [Look.flat(canopy)])
            blob.position = [Float.random(in: -0.4...0.4, using: &rng), trunkH + r * (0.5 + 0.7 * Float(j)),
                             Float.random(in: -0.4...0.4, using: &rng)]
            t.addChild(blob)
        }
        return t
    }

    /// Autumn leaf that can glow, breathe, pop and sink like a Micro orb. Hangs from its stem at the origin.
    static func leaf(_ color: UIColor, length: Float = 0.11) -> ModelEntity {
        let mesh = Meshes.leaf(length: length, width: length * 0.62) ?? .generateSphere(radius: length / 3)
        let e = ModelEntity(mesh: mesh, materials: [Look.glow(color)])
        e.components.set(OpacityComponent(opacity: 1))
        return e
    }
}

extension Rig {
    /// A frame at a given floor point and heading, for games that move the participant (Scary Balance).
    init(origin: SIMD3<Float>, yaw: Float, eye: Float) {
        self.origin = [origin.x, 0, origin.z]
        self.yaw = yaw
        self.eye = eye
    }
}
