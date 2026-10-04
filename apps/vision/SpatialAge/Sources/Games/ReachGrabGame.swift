import RealityKit
import ScoreKit
import simd

/// Reach and Grab. Gold cubes wait at set distances from the dominant shoulder. With feet planted, reach out and
/// touch each one. The distances climb past arm's length, so the last ones are won by leaning.
/// Spec: specs/games/reach-grab.md.
@MainActor
final class ReachGrabGame: Minigame {
    static let game = Game.reach
    /// Cube edge, meters.
    static let size: Float = 0.06
    /// Contact: fingertip within this (half the edge) plus `ReachTrial.contactSlack` of the cube center.
    static let radius: Float = 0.03
    /// A cube left untouched this long is a miss.
    static let window = 6.0
    static let pause = 0.6
    /// Shoulder to cube center, meters, nearest first. Both ladders climb the same rungs.
    static let rungs = [0.50, 0.58, 0.66, 0.74, 0.82, 0.90]
    /// Practice cubes, straight ahead and within easy reach.
    static let practice = [0.45, 0.55]
    /// Side ladder direction, degrees from straight ahead toward the dominant side.
    static let sideDeg = 45.0

    /// One planned cube. `azimuthDeg` is toward the dominant side, as logged. `rung` sets the pop pitch.
    private struct Slot {
        let ladder: Int
        let azimuthDeg: Double
        let distance: Double
        let rung: Int
    }

    let ctx: GameContext
    private var live: ModelEntity?

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var out: [ReachGrabTrial] = []
        var ended: Set<Int> = []
        var passed = 0
        for slot in plan(familiarization: familiarization) {
            guard out.count < trials, !Task.isCancelled else { break }
            passed += 1
            if ended.contains(slot.ladder) { ctx.hud.done = passed; continue }
            guard let trial = await present(index: out.count, slot) else { break }
            out.append(trial)
            ctx.hud.done = passed
            // A miss ends its ladder, since the next rung is farther. Practice always shows both cubes.
            if trial.outcome == .miss, !familiarization { ended.insert(slot.ladder) }
            await ctx.clock.wait(Self.pause)
        }
        return Block(task: .reachGrab, familiarization: familiarization, seed: seed, trials: out.map(Trial.reachGrab))
    }

    func teardown() { live?.removeFromParent(); live = nil }

    /// Practice is two cubes ahead. Scored is the two ladders interleaved, forward then side, nearest first.
    private func plan(familiarization: Bool) -> [Slot] {
        var slots: [Slot] = []
        if familiarization {
            for (r, d) in Self.practice.enumerated() {
                slots.append(Slot(ladder: 0, azimuthDeg: 0, distance: d, rung: r))
            }
            return slots
        }
        for (r, d) in Self.rungs.enumerated() {
            slots.append(Slot(ladder: 0, azimuthDeg: 0, distance: d, rung: r))
            slots.append(Slot(ladder: 1, azimuthDeg: Self.sideDeg, distance: d, rung: r))
        }
        return slots
    }

    /// Shows one cube and watches the fingertips until a grab or the timeout. Nil if the run is cancelled mid-trial.
    private func present(index: Int, _ slot: Slot) async -> ReachGrabTrial? {
        // reachPoint measures azimuth toward the right. A left-handed participant's dominant side is the left.
        let side: Double = ctx.handedness == .left ? -1 : 1
        let azimuth = slot.azimuthDeg * side
        let p = ctx.reachPoint(azimuthDeg: azimuth, elevationDeg: 0, reach: Float(slot.distance))
        let cube = Self.makeCube()
        cube.position = p
        // Square to the line from the shoulder, so the near face looks at the participant.
        cube.orientation = simd_quatf(angle: ctx.rig.yaw - Float(azimuth * .pi / 180), axis: [0, 1, 0])
        ctx.layer.addChild(cube)
        live = cube
        ctx.micro.appear(cube)
        // Spawn time: the first frame the cube is in the scene.
        _ = await ctx.clock.next()
        let spawn = ctx.now

        var grab: (hand: Hand, time: Double, lean: Double)?
        while ctx.now - spawn < Self.window, grab == nil, !Task.isCancelled {
            _ = await ctx.clock.next()
            let t = ctx.now - spawn
            if t > Theme.Motion.appear { ctx.micro.breathe(cube, t: t) }
            guard let near = ctx.nearestTip(to: p) else { continue }
            ctx.micro.glow(cube, color: Theme.gold, distance: near.distance)
            if near.distance <= Self.radius + ReachTrial.contactSlack {
                grab = (near.hand, ctx.tracker.state(near.hand)?.t ?? ctx.now, leanNow())
            }
        }
        live = nil

        let buffer = ctx.tracker.buffer
        guard let (hand, grabT, lean) = grab else {
            if Task.isCancelled { cube.removeFromParent(); return nil }
            ctx.micro.sink(cube)
            return ReachGrabTrial(index: index, azimuthDeg: slot.azimuthDeg, elevationDeg: 0, distanceM: slot.distance,
                                  position: p.v3, spawnT: spawn, grabT: nil, hand: nil, outcome: .miss, leanM: nil,
                                  trackingGapMs: buffer.maxGapMs(nil, spawn, spawn + Self.window))
        }
        // Pitch climbs one step per rung, so the ladder is audible. Speed is not what this game rewards.
        ctx.micro.pop(cube, color: Theme.paper, speedStep: slot.rung)
        return ReachGrabTrial(index: index, azimuthDeg: slot.azimuthDeg, elevationDeg: 0, distanceM: slot.distance,
                              position: p.v3, spawnT: spawn, grabT: grabT, hand: hand, outcome: .grab, leanM: lean,
                              trackingGapMs: buffer.maxGapMs(hand, spawn, grabT),
                              trace: buffer.trace(hand, spawn - ReachTrial.preRoll, grabT))
    }

    /// Horizontal head travel from the start pose (the rig origin, under the head when the game began), meters.
    private func leanNow() -> Double {
        let head = ctx.tracker.head().columns.3, origin = ctx.rig.origin
        let dx = head.x - origin.x, dz = head.z - origin.z
        return Double((dx * dx + dz * dz).squareRoot())
    }

    /// Gold cube that can glow, breathe, pop and sink like a Micro orb.
    private static func makeCube() -> ModelEntity {
        let s = Self.size
        let e = ModelEntity(mesh: .generateBox(width: s, height: s, depth: s, cornerRadius: s * 0.12),
                            materials: [Look.glow(Theme.gold)])
        e.components.set(OpacityComponent(opacity: 1))
        return e
    }
}
