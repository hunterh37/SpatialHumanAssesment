import RealityKit
import simd
import UIKit

/// Per-game set dressing from the Games Ideas deck, placed inside the Dusk stage while the game runs.
/// Nothing in a backdrop moves, so motion in view is still always a game signal. Unlit, like the stage.
@MainActor
enum Scenery {
    /// Forest clearing for Stick Drop and Spatial Tracking. The Dusk stage already rings the participant
    /// with trees past 6 m and along the far shore, so nothing is added near the targets.
    static func forest(rig: Rig) -> Entity {
        let root = Entity()
        root.name = "forest"
        root.position = rig.origin
        root.orientation = rig.rotation
        return root
    }

    /// Island and moat for Hole in the Wall: a stone platform under the participant, lake water to 2.6 m, grass beyond.
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
