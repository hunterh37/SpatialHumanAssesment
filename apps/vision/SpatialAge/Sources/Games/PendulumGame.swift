import Foundation
import RealityKit
import ScoreKit
import simd

/// Pendulum. A gold weight swings on a cord. The cord lets go at a random moment and the weight
/// falls under real gravity. Pinch it out of the air. Spec: specs/games/pendulum.md.
///
/// The swing and the fall are computed analytically every frame (no physics engine), so the release
/// state in the log is the exact start of the trajectory the participant saw.
@MainActor
final class PendulumGame: Minigame {
    static let game = Game.pendulum
    static let g: Float = 9.81
    /// Catch: grasp point (thumb-index midpoint) within this of the bob center, with the pinch closed.
    static let graspRadius: Float = 0.07
    static let closedAperture: Float = 0.045
    /// A drop is called once the bob has fallen this far, or reaches the floor.
    static let maxFall: Float = 1.0

    let ctx: GameContext
    private var ruler: Entity?
    private var pivot: SIMD3<Float> = .zero

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        let rig = ctx.rig
        pivot = rig.world([0, rig.eye + 0.4, -0.48])
        if ruler == nil {
            let r = Self.makeRuler(height: 1.2)
            r.position = rig.world([0, rig.eye + 0.4 - 1.2, -0.62])
            r.orientation = rig.rotation
            ctx.layer.addChild(r)
            ruler = r
        }
        var out: [Trial] = []
        for i in 0..<trials where !Task.isCancelled {
            let trial = await swing(index: i, rng: &rng)
            out.append(.pendulum(trial))
            ctx.hud.done = i + 1
            await ctx.clock.wait(0.8)
        }
        return Block(task: .pendulum, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() { ruler?.removeFromParent(); ruler = nil }

    private func swing(index: Int, rng: inout SeededRNG) async -> PendulumTrial {
        let length = Float.random(in: 0.55...0.85, using: &rng)
        let amp = Float.random(in: 22...34, using: &rng) * .pi / 180
        let swingT = Double.random(in: 1.5...4.0, using: &rng)
        let omega = (Self.g / length).squareRoot()
        let lateral = ctx.rig.rotation.act([1, 0, 0])

        let bob = Micro.orb(Theme.gold, radius: Theme.Size.bob)
        let cord = ModelEntity(mesh: .generateCylinder(height: 1, radius: 0.0015), materials: [Look.flat(Theme.paper)])
        ctx.layer.addChild(cord)
        ctx.layer.addChild(bob)

        func place(theta: Float) -> SIMD3<Float> {
            let p = pivot + lateral * (length * sin(theta)) + SIMD3<Float>(0, -length * cos(theta), 0)
            bob.position = p
            cord.position = (pivot + p) / 2
            cord.scale = [1, length, 1]
            cord.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(pivot - p))
            return p
        }
        _ = place(theta: amp)
        ctx.micro.appear(bob)

        // Swing until release. Glow tells the hand it is close; it never predicts the release.
        var t = 0.0
        while t < swingT, !Task.isCancelled {
            t += await ctx.clock.next()
            let p = place(theta: amp * cos(omega * Float(t)))
            if let near = nearestGrasp(to: p) { ctx.micro.glow(bob, color: Theme.gold, distance: near.distance) }
        }
        let theta = amp * cos(omega * Float(swingT))
        let thetaDot = -amp * omega * sin(omega * Float(swingT))
        let p0 = place(theta: theta)
        let v0 = lateral * (length * cos(theta) * thetaDot) + SIMD3<Float>(0, length * sin(theta) * thetaDot, 0)
        ctx.micro.snap(cord, pivot: pivot)
        let release = ctx.now
        let apertureRelease = ctx.tracker.state(ctx.dominant)?.aperture

        // Ballistic fall: p(tau) = p0 + v0 tau - g tau^2 / 2.
        var caught: (Hand, Double, SIMD3<Float>, Float)?
        var p = p0
        while caught == nil, !Task.isCancelled {
            _ = await ctx.clock.next()
            let tau = Float(ctx.now - release)
            p = p0 + v0 * tau + SIMD3<Float>(0, -0.5 * Self.g * tau * tau, 0)
            bob.position = p
            if p0.y - p.y > Self.maxFall || p.y < Theme.Size.bob { break }
            for (hand, s) in ctx.tracker.trackedHands
            where simd_distance(s.grasp, p) < Self.graspRadius && s.aperture < Self.closedAperture {
                caught = (hand, s.t, p, s.aperture)
            }
        }

        let gap = ctx.tracker.buffer.maxGapMs(caught?.0, release, caught?.1 ?? release + 0.6)
        guard let (hand, tCatch, pCatch, aperture) = caught else {
            await fallToFloor(bob, from: p, velocity: v0 + SIMD3<Float>(0, -Self.g * Float(ctx.now - release), 0))
            return PendulumTrial(index: index, lengthM: Double(length), amplitudeDeg: Double(amp * 180 / .pi),
                                 releaseT: release, releaseAngleDeg: Double(theta * 180 / .pi),
                                 releasePosition: p0.v3, releaseVelocity: v0.v3, catchT: nil, catchPosition: nil,
                                 hand: nil, outcome: .drop, trackingGapMs: gap,
                                 apertureReleaseM: apertureRelease.map(Double.init))
        }
        let latency = tCatch - release
        let outcome: PendulumTrial.Outcome = latency < PendulumMetrics.anticipationS ? .anticipation : .catch
        await celebrate(bob, hand: hand, at: pCatch, dropM: p0.y - pCatch.y)
        return PendulumTrial(index: index, lengthM: Double(length), amplitudeDeg: Double(amp * 180 / .pi),
                             releaseT: release, releaseAngleDeg: Double(theta * 180 / .pi),
                             releasePosition: p0.v3, releaseVelocity: v0.v3, catchT: tCatch,
                             catchPosition: pCatch.v3, hand: hand, outcome: outcome, trackingGapMs: gap,
                             apertureReleaseM: apertureRelease.map(Double.init), apertureCatchM: Double(aperture),
                             trace: ctx.tracker.buffer.trace(hand, release - 0.35, tCatch))
    }

    private func nearestGrasp(to p: SIMD3<Float>) -> (hand: Hand, distance: Float)? {
        ctx.tracker.trackedHands.map { ($0.0, simd_distance($0.1.grasp, p)) }.min { $0.1 < $1.1 }
    }

    /// Caught: the weight rides in the hand for a beat, a gold tick marks the height on the ruler.
    private func celebrate(_ bob: ModelEntity, hand: Hand, at p: SIMD3<Float>, dropM: Float) async {
        Tone.play(.caught, on: bob, gain: -10)
        ctx.micro.ring(at: p, color: Theme.gold, radius: Theme.Size.bob * 2)
        markRuler(height: p.y, dropCm: dropM * 100)
        var t = 0.0
        while t < 0.45 {
            t += await ctx.clock.next()
            if let s = ctx.tracker.state(hand) { bob.position = s.grasp }
        }
        ctx.micro.dissolve(bob)
    }

    private func fallToFloor(_ bob: ModelEntity, from p: SIMD3<Float>, velocity: SIMD3<Float>) async {
        var pos = p, v = velocity
        while pos.y > Theme.Size.bob {
            let dt = Float(await ctx.clock.next())
            v.y -= Self.g * dt
            pos += v * dt
            bob.position = pos
        }
        bob.position.y = Theme.Size.bob
        ctx.micro.sink(bob)
    }

    private func markRuler(height: Float, dropCm: Float) {
        guard let ruler else { return }
        let tick = ModelEntity(mesh: .generateBox(width: 0.09, height: 0.004, depth: 0.006), materials: [Look.flat(Theme.gold)])
        tick.position = [0, height - ruler.position.y, 0.004]
        ruler.addChild(tick)
        if let mesh = try? MeshResource.generateText(String(format: "%.0f cm", dropCm),
                                                     extrusionDepth: 0.001, font: .systemFont(ofSize: 0.025, weight: .semibold)) {
            let micro = ctx.micro
        let label = ModelEntity(mesh: mesh, materials: [Look.flat(Theme.gold)])
            label.position = [0.055, height - ruler.position.y - 0.01, 0.004]
            ruler.addChild(label)
            ctx.clock.animate(1.6, { _ in }, done: { [weak label] in label.map(micro.dissolve) })
        }
        let fade = ctx.micro
        ctx.clock.animate(2.4, { p in tick.scale.x = Float(1 - 0.5 * p) }, done: { [weak tick] in tick.map(fade.dissolve) })
    }

    /// Life-size centimeter ruler. Zero at the top, the way a dropped ruler reads.
    static func makeRuler(height: Float) -> Entity {
        let root = Entity()
        let face = ModelEntity(mesh: .generateBox(width: 0.07, height: height, depth: 0.004),
                               materials: [Look.flat(Theme.inkLift)])
        face.position.y = height / 2
        root.addChild(face)
        let ink = Look.flat(Theme.grid)
        for cm in 0...Int(height * 100) {
            let major = cm % 10 == 0, mid = cm % 5 == 0
            let w: Float = major ? 0.035 : mid ? 0.022 : 0.012
            let tick = ModelEntity(mesh: .generateBox(width: w, height: 0.0012, depth: 0.001), materials: [ink])
            tick.position = [-0.035 + w / 2, height - Float(cm) / 100, 0.0025]
            root.addChild(tick)
            if major, cm > 0, let mesh = try? MeshResource.generateText("\(cm)", extrusionDepth: 0.0005,
                                                                        font: .systemFont(ofSize: 0.014)) {
        let label = ModelEntity(mesh: mesh, materials: [ink])
                label.position = [0.004, height - Float(cm) / 100 - 0.005, 0.0025]
                root.addChild(label)
            }
        }
        return root
    }
}
