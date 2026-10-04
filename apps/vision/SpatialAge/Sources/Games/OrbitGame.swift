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
    /// Fingertip light trail, drawn while the tip is inside the orb. Brightness tracks steadiness.
    static let tipTrailSteps = 14
    /// Mean per-frame change of the tip-to-orb offset at which the trail is fully dimmed (meters).
    static let jitterFloorM: Float = 0.004
    /// Share of samples on target for the full success reward at the end of a trial.
    static let successShare = 0.5

    /// Path center below eye level and ahead, meters. The lowest point stays 0.16 m under the eyes.
    static let centerDrop = 0.08
    static let centerAhead = 0.45
    static let amplitude = V3(0.16, 0.07, 0.06)
    /// Head-yaw cone (radians) the path center may sit off the gaze before the frame turns to follow.
    static let followCone: Float = 0.35
    /// Fraction of the out-of-cone yaw error removed per second.
    static let followRate: Float = 3

    let ctx: GameContext
    /// Participant frame for the current trial. Re-taken from the live head pose before every trial so the
    /// orb starts in front of the participant even after they turn between trials.
    private var frame: Rig
    init(_ ctx: GameContext) { self.ctx = ctx; frame = ctx.rig }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        var out: [Trial] = []
        for i in 0..<trials where !Task.isCancelled {
            if let head = ctx.tracker.trackedHead() { frame = Rig(head: head) }
            let path = PursuitTrial.Path(
                center: V3(0, Double(frame.eye) - Self.centerDrop, -Self.centerAhead), amplitude: Self.amplitude,
                frequencyHz: V3(0.21, 0.29, 0.13),
                phase: V3(.random(in: 0..<6.283, using: &rng), .random(in: 0..<6.283, using: &rng),
                          .random(in: 0..<6.283, using: &rng)))
            out.append(.pursuit(await run(index: i, path: path, duration: familiarization ? 6 : Self.duration)))
            ctx.hud.done = i + 1
            await ctx.clock.wait(0.5)
        }
        return Block(task: .pursuit, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() {}

    /// Turns the participant frame toward the live head yaw when the gaze leaves the follow cone, so the orb
    /// stays in front instead of drifting beside or behind after a body turn. Samples use the same frame, so
    /// logged target and fingertip stay consistent.
    private func follow(_ dt: Double) {
        guard let head = ctx.tracker.trackedHead() else { return }
        let live = Rig(head: head)
        var err = live.yaw - frame.yaw
        err = atan2(sin(err), cos(err))
        let over = abs(err) - Self.followCone
        guard over > 0 else { return }
        frame.yaw += (err > 0 ? 1 : -1) * over * min(1, Self.followRate * Float(dt))
        frame.origin += (live.origin - frame.origin) * min(1, Self.followRate * Float(dt))
    }

    private func world(_ v: V3) -> SIMD3<Float> { frame.world([Float(v.x), Float(v.y), Float(v.z)]) }

    private func local(_ p: SIMD3<Float>) -> V3 {
        let l = frame.rotation.inverse.act(p - frame.origin)
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

        let tipTrail = TipTrail(steps: Self.tipTrailSteps, parent: ctx.layer)

        // Acquisition: the orb waits, breathing, until a fingertip rests inside it for 0.5 s (or 10 s pass).
        var inside = 0.0, waited = 0.0
        while inside < 0.5 && waited < 10, !Task.isCancelled {
            let dt = await ctx.clock.next()
            waited += dt
            follow(dt)
            orb.position = world(path.position(at: 0))
            ctx.micro.breathe(orb, t: waited)
            let d = ctx.nearestTip(to: orb.position)?.distance ?? .infinity
            ctx.micro.glow(orb, color: Theme.teal, distance: d)
            inside = d <= OrbitMetrics.onTargetM.float ? inside + dt : 0
        }
        orb.scale = .one
        if inside >= 0.5 { Tone.play(.lock, on: orb, gain: -16) }

        let start = ctx.now
        var ts: [Double] = [], targets: [V3] = [], fingers: [V3?] = []
        var nextSample = 0.0
        var used: [Hand: Int] = [:]
        while ctx.now - start < duration, !Task.isCancelled {
            let dt = await ctx.clock.next()
            follow(dt)
            let tau = ctx.now - start
            let target = path.position(at: tau)
            orb.position = world(target)
            for (k, e) in trail.enumerated() {
                e.position = world(path.position(at: tau + Self.trailLead * Double(k + 1) / Double(Self.trailSteps)))
            }
            let near = ctx.nearestTip(to: orb.position)
            ctx.micro.glow(orb, color: Theme.teal, distance: near?.distance ?? .infinity)
            if let near, near.distance <= OrbitMetrics.onTargetM.float {
                tipTrail.push(tip: near.tip, offset: near.tip - orb.position)
            } else {
                tipTrail.retract()
            }
            tipTrail.draw()
            if tau >= nextSample {
                ts.append(ctx.now); targets.append(target)
                fingers.append(near.map { local($0.tip) })
                if let h = near?.hand { used[h, default: 0] += 1 }
                nextSample += 1 / Self.sampleHz
            }
        }
        // Pursuit end: the full reward when the tip stayed inside for at least half the trial, else a small
        // burst, the quiet miss and a streak reset.
        let onTarget = zip(fingers, targets).filter { f, t in
            guard let f else { return false }
            return f.distance(to: t) <= OrbitMetrics.onTargetM
        }.count
        if !ts.isEmpty, Double(onTarget) / Double(ts.count) >= Self.successShare {
            ctx.micro.pop(orb, color: Theme.teal, speedStep: 3)
            ctx.cheer()
        } else {
            Tone.play(.miss, on: orb, gain: -20)
            ctx.micro.juice.reset()
            ctx.micro.pop(orb, color: Theme.teal, speedStep: 1, reward: .light)
        }
        trail.forEach { ctx.micro.dissolve($0) }
        tipTrail.entities.forEach { ctx.micro.dissolve($0) }
        let hand = used.max { $0.value < $1.value }?.key
        return PursuitTrial(index: index, startT: start, durationS: duration, path: path, t: ts, target: targets,
                            finger: fingers, hand: hand,
                            trackingGapMs: ctx.tracker.buffer.maxGapMs(hand, start, ctx.now))
    }
}

/// Hover trail behind the fingertip. Each frame the tip is inside the orb a point is added; outside,
/// the tail retracts. Opacity scales with steadiness: the mean frame-to-frame change of the tip's
/// offset from the orb, so following the orb smoothly reads bright and tremor reads dim.
@MainActor
private final class TipTrail {
    let entities: [ModelEntity]
    private var tips: [SIMD3<Float>] = []
    private var offsets: [SIMD3<Float>] = []
    private var steadiness: Float = 1

    init(steps: Int, parent: Entity) {
        entities = (0..<steps).map { k in
            let r = Theme.Size.orb * 0.22 * (1 - 0.75 * Float(k) / Float(max(steps - 1, 1)))
            let e = Micro.orb(Theme.paper, radius: r)
            e.model?.materials = [Look.glow(Theme.teal, intensity: 2.4)]
            e.components[OpacityComponent.self]?.opacity = 0
            parent.addChild(e)
            return e
        }
    }

    func push(tip: SIMD3<Float>, offset: SIMD3<Float>) {
        tips.append(tip)
        offsets.append(offset)
        if tips.count > entities.count { tips.removeFirst(); offsets.removeFirst() }
        guard offsets.count > 1 else { return }
        var jitter: Float = 0
        for i in 1..<offsets.count { jitter += simd_distance(offsets[i], offsets[i - 1]) }
        jitter /= Float(offsets.count - 1)
        let target = max(0, 1 - jitter / OrbitGame.jitterFloorM)
        steadiness += (target - steadiness) * 0.2
    }

    func retract() {
        let n = min(2, tips.count)
        tips.removeFirst(n)
        offsets.removeFirst(n)
    }

    func draw() {
        for (k, e) in entities.enumerated() {
            let i = tips.count - 1 - k
            guard i >= 0 else { e.components[OpacityComponent.self]?.opacity = 0; continue }
            e.position = tips[i]
            let age = Float(k) / Float(entities.count)
            e.components[OpacityComponent.self]?.opacity = (1 - age) * (0.25 + 0.6 * steadiness)
        }
    }
}

private extension Double {
    var float: Float { Float(self) }
}
