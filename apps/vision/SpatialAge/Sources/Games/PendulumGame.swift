import Foundation
import RealityKit
import ScoreKit
import simd

/// Stick Drop (task `pendulum`). A row of gold leaves hangs from a branch across the view, in a forest clearing.
/// One leaf lets go at a random moment and falls; touch it with any part of a hand before it reaches the ground. Leaves sit from 60 degrees
/// left to 60 degrees right, so the drop can come from the edge of vision, and the fall speeds up over the block.
/// Spec: specs/games/pendulum.md (Games Ideas deck, "Stick Drop").
///
/// The fall is analytic, `p0 - g s tau^2 / 2` with gravity scale `s`, so the logged release state is the exact
/// start of the trajectory the participant saw.
@MainActor
final class PendulumGame: Minigame {
    static let game = Game.pendulum
    static let g: Float = 9.81
    /// Catch: any hand joint or bone within this of the leaf center. No pinch needed.
    static let contactRadius: Float = 0.065
    /// Leaf azimuths from head forward, degrees. Fixed, so every session tests the same field.
    static let azimuths: [Float] = [-60, -40, -20, 0, 20, 40, 60]
    /// Horizontal distance from the head to each stem, and stem height above the eyes, meters.
    static let reach: Float = 0.52
    static let stemAboveEye: Float = 0.12
    static let leafLength: Float = 0.11
    /// Gravity scale ramps from slow to real over the scored block. Practice stays slow.
    static let slowest = 0.25, fastest = 1.0, practiceScale = 0.25
    /// Wait between the last leaf settling and the next release, seconds.
    static let foreperiod: ClosedRange<Double> = 1.0...3.0

    let ctx: GameContext
    private var scenery: Entity?
    private var branch: Entity?
    private var leaves: [ModelEntity?] = []
    private var stems: [SIMD3<Float>] = []

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        if scenery == nil { build() }
        // Each leaf falls equally often: shuffled passes over the row.
        var order: [Int] = []
        while order.count < trials { order += Array(Self.azimuths.indices).shuffled(using: &rng) }

        var out: [Trial] = []
        for i in 0..<trials where !Task.isCancelled {
            let scale = familiarization ? Self.practiceScale
                : Self.slowest + (Self.fastest - Self.slowest) * Double(i) / Double(max(trials - 1, 1))
            await ctx.clock.wait(Double.random(in: Self.foreperiod, using: &rng))
            guard let trial = await drop(index: i, leaf: order[i], scale: scale) else { break }
            out.append(.pendulum(trial))
            ctx.hud.done = i + 1
            regrow(order[i])
            await ctx.clock.wait(0.4)
        }
        return Block(task: .pendulum, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() {
        scenery?.removeFromParent(); scenery = nil
        branch?.removeFromParent(); branch = nil
        leaves.forEach { $0?.removeFromParent() }
        leaves = []
    }

    /// Forest, branch arc and one leaf per stem.
    private func build() {
        let rig = ctx.rig
        let forest = Scenery.forest(rig: rig)
        ctx.layer.addChild(forest)
        scenery = forest

        let y = rig.eye + Self.stemAboveEye
        stems = Self.azimuths.map { az in
            let a = az * .pi / 180
            return rig.world([sin(a) * Self.reach, y, -cos(a) * Self.reach])
        }
        // Branch: one bark segment between neighboring stems, overhanging both ends.
        let b = Entity()
        let ends = [stems[0] + (stems[0] - stems[1]) * 0.4] + stems + [stems[stems.count - 1] + (stems[stems.count - 1] - stems[stems.count - 2]) * 0.4]
        for k in 1..<ends.count {
            let a = ends[k - 1] + [0, 0.012, 0], c = ends[k] + [0, 0.012, 0]
            let seg = ModelEntity(mesh: .generateCylinder(height: simd_distance(a, c), radius: 0.012),
                                  materials: [Look.flat(Theme.bark)])
            seg.position = (a + c) / 2
            seg.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(c - a))
            b.addChild(seg)
        }
        ctx.layer.addChild(b)
        branch = b
        leaves = stems.indices.map { _ in nil }
        for i in stems.indices { regrow(i) }
    }

    /// Hangs a fresh leaf at stem `i`, facing the participant.
    private func regrow(_ i: Int) {
        guard leaves.indices.contains(i) else { return }
        let leaf = Scenery.leaf(Theme.gold, length: Self.leafLength)
        leaf.position = stems[i]
        leaf.orientation = faceRig(at: stems[i])
        ctx.layer.addChild(leaf)
        ctx.micro.appear(leaf)
        leaves[i] = leaf
    }

    private func faceRig(at p: SIMD3<Float>) -> simd_quatf {
        let o = ctx.rig.origin
        return simd_quatf(angle: atan2(o.x - p.x, o.z - p.z), axis: [0, 1, 0])
    }

    /// Releases leaf `index` and watches for hand contact until it lands. Nil if the run is cancelled.
    private func drop(index: Int, leaf i: Int, scale: Double) async -> PendulumTrial? {
        guard let leaf = leaves[i] else { return nil }
        let half = Self.leafLength / 2
        let p0 = stems[i] - [0, half, 0]
        let gs = Self.g * Float(scale)
        // Release: the stem snaps with a tock; the first falling frame is the release time.
        Tone.play(.tock, on: leaf, gain: -8)
        _ = await ctx.clock.next()
        let release = ctx.now
        let ecc = ctx.eccentricity(of: p0)
        let apertureRelease = ctx.tracker.state(ctx.dominant)?.aperture
        let spin = Float.random(in: 1.5...3.0) * (Bool.random() ? 1 : -1)
        let face = leaf.orientation

        var caught: (Hand, Double, SIMD3<Float>, Float)?
        var p = p0
        while caught == nil, !Task.isCancelled {
            _ = await ctx.clock.next()
            let tau = Float(ctx.now - release)
            p = p0 + SIMD3<Float>(0, -0.5 * gs * tau * tau, 0)
            if p.y - half < 0.01 { break }
            leaf.position = p + [0, half, 0]
            // A slow turn as it falls. Visual only: contact uses the analytic center.
            leaf.orientation = simd_quatf(angle: spin * tau, axis: [0, 1, 0]) * face
            if let near = nearestHand(to: p) {
                ctx.micro.glow(leaf, color: Theme.gold, distance: near.distance)
                if near.distance < Self.contactRadius, let s = ctx.tracker.state(near.hand) {
                    caught = (near.hand, s.t, p, s.aperture)
                }
            }
        }
        leaves[i] = nil
        guard !Task.isCancelled else { leaf.removeFromParent(); return nil }

        let releaseAngle = Double(Self.azimuths[i])
        let gap = ctx.tracker.buffer.maxGapMs(caught?.0, release, caught?.1 ?? ctx.now)
        guard let (hand, tCatch, pCatch, aperture) = caught else {
            leaf.position.y = 0.012
            ctx.micro.sink(leaf)
            return PendulumTrial(index: index, lengthM: 0, amplitudeDeg: 0, releaseT: release,
                                 releaseAngleDeg: releaseAngle, releasePosition: p0.v3, releaseVelocity: .zero,
                                 catchT: nil, catchPosition: nil, hand: nil, outcome: .drop, trackingGapMs: gap,
                                 apertureReleaseM: apertureRelease.map(Double.init), stickIndex: i,
                                 eccentricityDeg: ecc, gravityScale: scale)
        }
        let latency = tCatch - release
        let outcome: PendulumTrial.Outcome = latency < PendulumMetrics.anticipationS ? .anticipation : .catch
        await celebrate(leaf, hand: hand, at: pCatch)
        return PendulumTrial(index: index, lengthM: 0, amplitudeDeg: 0, releaseT: release,
                             releaseAngleDeg: releaseAngle, releasePosition: p0.v3, releaseVelocity: .zero,
                             catchT: tCatch, catchPosition: pCatch.v3, hand: hand, outcome: outcome,
                             trackingGapMs: gap, apertureReleaseM: apertureRelease.map(Double.init),
                             apertureCatchM: Double(aperture),
                             trace: ctx.tracker.buffer.trace(hand, release - 0.35, tCatch),
                             stickIndex: i, eccentricityDeg: ecc, gravityScale: scale)
    }

    private func nearestHand(to p: SIMD3<Float>) -> (hand: Hand, distance: Float)? {
        ctx.tracker.trackedHands.map { ($0.0, $0.1.contactDistance(to: p)) }.min { $0.1 < $1.1 }
    }

    /// Caught: the leaf rides in the hand for a beat with a gold ring, then fades.
    private func celebrate(_ leaf: ModelEntity, hand: Hand, at p: SIMD3<Float>) async {
        Tone.play(.caught, on: leaf, gain: -10)
        ctx.micro.ring(at: p, color: Theme.gold, radius: Self.leafLength)
        ctx.cheer()
        let half = Self.leafLength / 2
        var t = 0.0
        while t < 0.45 {
            t += await ctx.clock.next()
            if let s = ctx.tracker.state(hand) { leaf.position = s.grasp + [0, half, 0] }
        }
        ctx.micro.dissolve(leaf)
    }
}
