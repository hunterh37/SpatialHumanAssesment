import RealityKit
import simd
import UIKit

/// The fully immersive environment: an ink sky dome, a soft horizon band, and a floor grid disc.
/// Nothing in the environment moves, so every motion in view is a game signal.
@MainActor
enum Stage {
    static func make() -> Entity {
        let root = Entity()
        root.name = "stage"

        if let sky = Meshes.invertedSphere(radius: Theme.Size.skyRadius) {
            root.addChild(ModelEntity(mesh: sky, materials: [Look.flat(Theme.ink)]))
        }
        // Horizon: a faint band at eye level that gives the dark a scale.
        // Open tube: a capped cylinder's bottom disc covers the sky for a seated eye below 1.2 m.
        if let tube = Meshes.innerTube(radius: Theme.Size.skyRadius * 0.9, height: 0.6) {
            let band = ModelEntity(mesh: tube, materials: [Look.flat(Theme.inkLift)])
            band.position.y = 1.5
            root.addChild(band)
        }

        let floor = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: Theme.Size.floorRadius),
                                materials: [Look.flat(Theme.inkLift)])
        root.addChild(floor)
        // Grid: rings every meter and 12 spokes, hairline, so depth reads at life scale.
        let line = Look.flat(Theme.mute.withAlphaComponent(0.35))
        for r in 1...Int(Theme.Size.floorRadius) {
            if let ring = Meshes.ring(radius: Float(r), thickness: 0.003, segments: 96, sides: 4) {
                let e = ModelEntity(mesh: ring, materials: [line])
                e.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                e.position.y = 0.003
                root.addChild(e)
            }
        }
        for i in 0..<12 {
            let spoke = ModelEntity(mesh: .generateBox(width: 0.004, height: 0.001, depth: Theme.Size.floorRadius),
                                    materials: [line])
            let a = Float(i) / 12 * 2 * .pi
            spoke.orientation = simd_quatf(angle: a, axis: [0, 1, 0])
            spoke.position = simd_quatf(angle: a, axis: [0, 1, 0]).act([0, 0.003, -Theme.Size.floorRadius / 2])
            root.addChild(spoke)
        }
        return root
    }
}

/// A frame at the participant: origin under the head, -Z is where they faced when the game began.
struct Rig {
    var origin: SIMD3<Float>
    var yaw: Float

    init(head: simd_float4x4) {
        let p = head.columns.3
        let f = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
        origin = [p.x, 0, p.z]
        yaw = simd_length(f) > 1e-3 ? atan2(-f.x, -f.z) : 0
        eye = p.y
    }

    var eye: Float

    /// Local (x right, y up, z forward negative) to world.
    func world(_ local: SIMD3<Float>) -> SIMD3<Float> {
        origin + simd_quatf(angle: yaw, axis: [0, 1, 0]).act(local)
    }

    var rotation: simd_quatf { simd_quatf(angle: yaw, axis: [0, 1, 0]) }
}
