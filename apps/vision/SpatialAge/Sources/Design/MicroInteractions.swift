import RealityKit
import simd
import UIKit

/// The five micro-interaction primitives. Every game composes these and nothing else,
/// so the whole catalog moves with one voice. Spec: specs/games/design.md.
@MainActor
struct Micro {
    let clock: FrameClock
    let root: Entity

    /// Target that can glow, breathe, pop and sink.
    static func orb(_ color: UIColor, radius: Float) -> ModelEntity {
        let e = ModelEntity(mesh: .generateSphere(radius: radius), materials: [Look.glow(color)])
        e.components.set(OpacityComponent(opacity: 1))
        return e
    }

    /// Appear: 60 ms ease-out from zero. Spawn time is the first frame it is drawn.
    func appear(_ e: Entity) {
        e.scale = .init(repeating: 0.001)
        clock.animate(Theme.Motion.appear) { p in e.scale = .init(repeating: Float(Ease.out(p))) }
    }

    /// 1. Breathe. Call every frame with the time since spawn.
    /// Off under Reduce Motion (Dusk spec section 8).
    func breathe(_ e: Entity, t: Double) {
        guard !UIAccessibility.isReduceMotionEnabled else { e.scale = .one; return }
        let s = 1 + Theme.Motion.breatheDepth * Float(sin(2 * .pi * Theme.Motion.breatheHz * t))
        e.scale = .init(repeating: s)
    }

    /// 2. Proximity glow. Emissive rises with the square of closeness, so it accelerates as the finger lands.
    func glow(_ e: ModelEntity, color: UIColor, distance: Float) {
        let c = max(0, 1 - distance / Theme.Motion.glowRange)
        e.model?.materials = [Look.glow(color, intensity: 0.6 + 2.4 * c * c)]
    }

    /// 3. Contact pop and ring. `speedStep` 0 to 6 sets the tick pitch: faster reach, higher note.
    func pop(_ e: Entity, color: UIColor, speedStep: Int) {
        let at = e.position(relativeTo: nil)
        Tone.play(.pop(step: speedStep), on: e)
        clock.animate(Theme.Motion.pop, { p in
            let s = p < 0.33 ? 1 + 0.25 * Float(p / 0.33) : 1.25 * Float(1 - (p - 0.33) / 0.67)
            e.scale = .init(repeating: max(s, 0.001))
        }, done: { e.removeFromParent() })
        ring(at: at, color: color, radius: (e as? ModelEntity)?.model?.mesh.bounds.extents.x ?? 0.06)
    }

    func ring(at: SIMD3<Float>, color: UIColor, radius: Float) {
        guard let mesh = Meshes.ring(radius: radius / 2, thickness: 0.0025) else { return }
        let r = ModelEntity(mesh: mesh, materials: [Look.flat(color)])
        r.position = at
        r.components.set(BillboardComponent())
        r.components.set(OpacityComponent(opacity: 1))
        root.addChild(r)
        clock.animate(Theme.Motion.ring, { p in
            let q = Float(Ease.out(p))
            r.scale = .init(repeating: 1 + (Theme.Motion.ringScale - 1) * q)
            r.components[OpacityComponent.self]?.opacity = 1 - q
        }, done: { r.removeFromParent() })
    }

    /// 4. Miss sink. Desaturate, drop 3 cm, fade. Quiet, so a miss never feels like a punishment.
    func sink(_ e: ModelEntity, sound: Bool = true) {
        e.model?.materials = [Look.glow(Theme.mute, intensity: 0.1)]
        if sound { Tone.play(.miss, on: e, gain: -20) }
        let y = e.position.y
        clock.animate(Theme.Motion.sink, { p in
            e.position.y = y - Theme.Motion.sinkDepth * Float(Ease.out(p))
            e.components[OpacityComponent.self]?.opacity = Float(1 - p)
        }, done: { e.removeFromParent() })
    }

    /// Correct no-go: the orange simply fades. No sound, no reward for inaction.
    func dissolve(_ e: Entity) {
        clock.animate(0.2, { p in e.components[OpacityComponent.self]?.opacity = Float(1 - p) },
                      done: { e.removeFromParent() })
    }

    /// 5. Release snap. The cord flicks upward and vanishes with a low tock.
    func snap(_ cord: Entity, pivot: SIMD3<Float>) {
        Tone.play(.tock, on: cord, gain: -8)
        cord.components.set(OpacityComponent(opacity: 1))
        let start = cord.scale
        clock.animate(Theme.Motion.snap, { p in
            let q = Float(Ease.out(p))
            cord.scale = [start.x, start.y * (1 - 0.6 * q), start.z]
            cord.components[OpacityComponent.self]?.opacity = 1 - q
        }, done: { cord.removeFromParent() })
    }

    /// Reach speed to a 0-6 pitch step: 0.3 s reach is top, 0.9 s is bottom.
    static func speedStep(reachTime: Double) -> Int { Int((6 * (0.9 - reachTime) / 0.6).rounded()).clamped(0, 6) }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
