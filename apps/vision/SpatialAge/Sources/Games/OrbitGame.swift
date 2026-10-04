import RealityKit
import ScoreKit
import simd

/// Orbit. A teal light drifts on a slow 3D path. Keep your fingertip inside it.
/// Spec: specs/games/orbit.md.
///
/// Pursuit samples are stored in the participant frame (origin under the head at game start,
/// -z forward) so the logged Lissajous path reproduces the target exactly.
@MainActor
final class OrbitGame: Minigame {
    static let game = Game.orbit
    static let duration = 12.0
    static let sampleHz = 30.0
    static let trailSteps = 6
    static let trailLead = 0.3

    let ctx: GameContext
    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        var out: [Trial] = []
        for i in 0..<trials where !Task.isCancelled {
            let path = PursuitTrial.Path(
                center: V3(0, Double(ctx.rig.eye) - 0.2, -0.45), amplitude: V3(0.2, 0.12, 0.08),
                frequencyHz: V3(0.21, 0.29, 0.13),
                phase: V3(.random(in: 0..<6.283, using: &rng), .random(in: 0..<6.283, using: &rng),
                          .random(in: 0..<6.283, using: &rng)))
            out.append(.pursuit(await run(index: i, path: path, duration: familiarization ? 6 : Self.duration)))
            ctx.hud.done = i + 1
            await ctx.clock.wait(1.0)
        }
        return Block(task: .pursuit, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() {}

    private func world(_ v: V3) -> SIMD3<Float> { ctx.rig.world([Float(v.x), Float(v.y), Float(v.z)]) }

    private func local(_ p: SIMD3<Float>) -> V3 {
        let l = ctx.rig.rotation.inverse.act(p - ctx.rig.origin)
        return V3(Double(l.x), Double(l.y), Double(l.z))
    }

    private func run(index: Int, path: PursuitTrial.Path, duration: Double) async -> PursuitTrial {
        let orb = Micro.orb(Theme.teal, radius: Theme.Size.orb)
        orb.position = world(path.position(at: 0))
        ctx.layer.addChild(orb)
        ctx.micro.appear(orb)
        let trail = (1...Self.trailSteps).map { k -> ModelEntity in
            let e = Micro.orb(Theme.teal, radius: Theme.Size.orb * (0.35 - 0.04 * Float(k)))
            e.components[OpacityComponent.self]?.opacity = 0.5 - 0.07 * Float(k)
            ctx.layer.addChild(e)
            return e
        }

        // Acquisition: the orb waits, breathing, until a fingertip rests inside it for 0.5 s (or 10 s pass).
        var inside = 0.0, waited = 0.0
        while inside < 0.5 && waited < 10, !Task.isCancelled {
            let dt = await ctx.clock.next()
            waited += dt
            ctx.micro.breathe(orb, t: waited)
            let d = ctx.nearestTip(to: orb.position)?.distance ?? .infinity
            ctx.micro.glow(orb, color: Theme.teal, distance: d)
            inside = d <= OrbitMetrics.onTargetM.float ? inside + dt : 0
        }
        orb.scale = .one

        let start = ctx.now
        var ts: [Double] = [], targets: [V3] = [], fingers: [V3?] = []
        var nextSample = 0.0
        var used: [Hand: Int] = [:]
        while ctx.now - start < duration, !Task.isCancelled {
            _ = await ctx.clock.next()
            let tau = ctx.now - start
            let target = path.position(at: tau)
            orb.position = world(target)
            for (k, e) in trail.enumerated() {
                e.position = world(path.position(at: tau + Self.trailLead * Double(k + 1) / Double(Self.trailSteps)))
            }
            let near = ctx.nearestTip(to: orb.position)
            ctx.micro.glow(orb, color: Theme.teal, distance: near?.distance ?? .infinity)
            if tau >= nextSample {
                ts.append(ctx.now); targets.append(target)
                fingers.append(near.map { local($0.tip) })
                if let h = near?.hand { used[h, default: 0] += 1 }
                nextSample += 1 / Self.sampleHz
            }
        }
        ctx.micro.pop(orb, color: Theme.teal, speedStep: 3)
        trail.forEach { ctx.micro.dissolve($0) }
        let hand = used.max { $0.value < $1.value }?.key
        return PursuitTrial(index: index, startT: start, durationS: duration, path: path, t: ts, target: targets,
                            finger: fingers, hand: hand,
                            trackingGapMs: ctx.tracker.buffer.maxGapMs(hand, start, ctx.now))
    }
}

private extension Double {
    var float: Float { Float(self) }
}
