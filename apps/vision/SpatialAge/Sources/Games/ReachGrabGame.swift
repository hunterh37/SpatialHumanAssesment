import RealityKit
import ScoreKit
import simd

/// Scary Balance (task `reach_grab`). Objects are spread around the room. A glowing spot on the floor says where
/// to stand; once there, a gold cube appears a set distance from the dominant shoulder and the participant reaches
/// for it with feet planted. Distances climb past arm's length, so the last ones are won by leaning. On some
/// trials a friendly creature drifts past mid-reach: freeze in place, arm out, until it is gone, then finish the
/// reach. Spec: specs/games/reach-grab.md (Games Ideas deck, "Scary Balance").
@MainActor
final class ReachGrabGame: Minigame {
    static let game = Game.reach
    /// Cube edge, meters.
    static let size: Float = 0.06
    /// Contact: fingertip within this (half the edge) plus `ReachTrial.contactSlack` of the cube center.
    static let radius: Float = 0.03
    /// A cube left untouched this long (not counting a freeze) is a miss.
    static let window = 6.0
    static let pause = 0.6
    /// Shoulder to cube center, meters, nearest first. Both ladders climb the same rungs.
    static let rungs = [0.50, 0.58, 0.66, 0.74, 0.82, 0.90]
    static let practice = [0.45, 0.55]
    /// Side ladder direction, degrees from the facing direction toward the dominant side.
    static let sideDeg = 45.0
    /// Floor spots, start-frame local (x right, z forward negative), meters. Kept within 0.8 m of the start so the
    /// walk stays inside the immersive boundary. The participant faces outward from the start at each one.
    static let spots: [SIMD2<Float>] = [[0, -0.6], [0.6, -0.3], [-0.6, -0.3], [0.45, 0.45], [-0.45, 0.45], [0, 0]]
    static let arriveRadius: Float = 0.25
    static let walkLimit = 12.0
    /// Freeze: about one scored trial in three, at a random moment mid-reach. Practice freezes on its second cube.
    static let freezeShare = 0.34
    static let freezeAfter: ClosedRange<Double> = 0.7...1.3
    static let creatureTime = 3.0

    private struct Slot {
        let ladder: Int
        let azimuthDeg: Double
        let distance: Double
        let rung: Int
        let spot: Int
        let freeze: Bool
    }

    let ctx: GameContext
    private var live: [Entity] = []

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        var out: [ReachGrabTrial] = []
        var ended: Set<Int> = []
        var passed = 0
        let base = ctx.hud.line
        for slot in plan(familiarization: familiarization, rng: &rng) {
            guard out.count < trials, !Task.isCancelled else { break }
            passed += 1
            if ended.contains(slot.ladder) { ctx.hud.done = passed; continue }
            guard let trial = await present(index: out.count, slot) else { break }
            out.append(trial)
            ctx.hud.done = passed
            if trial.outcome == .miss, !familiarization { ended.insert(slot.ladder) }
            await ctx.clock.wait(Self.pause)
        }
        ctx.hud.line = base
        return Block(task: .reachGrab, familiarization: familiarization, seed: seed, trials: out.map(Trial.reachGrab))
    }

    func teardown() { live.forEach { $0.removeFromParent() }; live = [] }

    /// Practice: two cubes ahead from the start spot. Scored: the two ladders interleaved, forward then side,
    /// nearest first, each cube at the next floor spot.
    private func plan(familiarization: Bool, rng: inout SeededRNG) -> [Slot] {
        if familiarization {
            return Self.practice.enumerated().map { r, d in
                Slot(ladder: 0, azimuthDeg: 0, distance: d, rung: r, spot: 0, freeze: r == 1)
            }
        }
        var slots: [Slot] = []
        for (r, d) in Self.rungs.enumerated() {
            for ladder in 0..<2 {
                let k = slots.count
                slots.append(Slot(ladder: ladder, azimuthDeg: ladder == 0 ? 0 : Self.sideDeg, distance: d, rung: r,
                                  spot: k % Self.spots.count, freeze: Double.random(in: 0..<1, using: &rng) < Self.freezeShare))
            }
        }
        return slots
    }

    /// Walk to the spot, then one cube with an optional freeze. Nil if the run is cancelled mid-trial.
    private func present(index: Int, _ slot: Slot) async -> ReachGrabTrial? {
        guard let local = await walk(to: slot.spot) else { return nil }
        ctx.hud.line = "Reach for the cube. Keep your feet still."
        let side: Double = ctx.handedness == .left ? -1 : 1
        let azimuth = slot.azimuthDeg * side
        let shoulder = SIMD3<Float>(ctx.handedness == .left ? -0.18 : 0.18, local.eye - 0.25, 0)
        let a = Float(azimuth * .pi / 180)
        let p = local.world(shoulder + SIMD3<Float>(sin(a), 0, -cos(a)) * Float(slot.distance))
        let cube = Self.makeCube()
        cube.position = p
        cube.orientation = simd_quatf(angle: local.yaw - a, axis: [0, 1, 0])
        ctx.layer.addChild(cube)
        live.append(cube)
        ctx.micro.appear(cube)
        _ = await ctx.clock.next()
        let spawn = ctx.now
        let freezeAt = slot.freeze ? spawn + Double.random(in: Self.freezeAfter) : .infinity

        var grab: (hand: Hand, time: Double, lean: Double)?
        var freeze: ReachGrabTrial.Freeze?
        var paused = 0.0
        while ctx.now - spawn - paused < Self.window, grab == nil, !Task.isCancelled {
            _ = await ctx.clock.next()
            if freeze == nil, ctx.now >= freezeAt {
                let f0 = ctx.now
                guard let f = await hold(cube: p, rig: local) else { break }
                freeze = f
                paused += ctx.now - f0
                continue
            }
            let t = ctx.now - spawn
            if t > Theme.Motion.appear { ctx.micro.breathe(cube, t: t) }
            guard let near = ctx.nearestTip(to: p) else { continue }
            ctx.micro.glow(cube, color: Theme.gold, distance: near.distance)
            if near.distance <= Self.radius + ReachTrial.contactSlack {
                grab = (near.hand, ctx.tracker.state(near.hand)?.t ?? ctx.now, lean(from: local))
            }
        }
        live.removeAll { $0 === cube }

        let buffer = ctx.tracker.buffer
        let stand = local.origin.v3
        guard let (hand, grabT, lean) = grab else {
            if Task.isCancelled { cube.removeFromParent(); return nil }
            ctx.micro.sink(cube)
            return ReachGrabTrial(index: index, azimuthDeg: slot.azimuthDeg, elevationDeg: 0, distanceM: slot.distance,
                                  position: p.v3, spawnT: spawn, grabT: nil, hand: nil, outcome: .miss, leanM: nil,
                                  trackingGapMs: buffer.maxGapMs(nil, spawn, ctx.now), standAt: stand, freeze: freeze)
        }
        ctx.micro.pop(cube, color: Theme.paper, speedStep: slot.rung)
        return ReachGrabTrial(index: index, azimuthDeg: slot.azimuthDeg, elevationDeg: 0, distanceM: slot.distance,
                              position: p.v3, spawnT: spawn, grabT: grabT, hand: hand, outcome: .grab, leanM: lean,
                              trackingGapMs: buffer.maxGapMs(hand, spawn, grabT),
                              trace: buffer.trace(hand, spawn - ReachTrial.preRoll, grabT), standAt: stand, freeze: freeze)
    }

    /// Shows the floor spot and waits for the head to be over it. Returns a frame there, facing out from the start.
    private func walk(to k: Int) async -> Rig? {
        let start = ctx.rig
        let s = Self.spots[k]
        let spot = start.world([s.x, 0, s.y])
        // Face away from the start; the center spot faces the start direction.
        let out = SIMD2<Float>(s.x, s.y)
        let yaw = simd_length(out) > 0.1 ? start.yaw + atan2(-out.x, -out.y) : start.yaw
        ctx.hud.line = "Walk to the glowing spot."
        let marker = Self.makeSpot()
        marker.position = spot + [0, 0.01, 0]
        ctx.layer.addChild(marker)
        live.append(marker)
        ctx.micro.appear(marker)
        var t = 0.0
        var head = ctx.tracker.head().columns.3
        while t < Self.walkLimit, !Task.isCancelled {
            t += await ctx.clock.next()
            ctx.micro.breathe(marker, t: t)
            head = ctx.tracker.head().columns.3
            if simd_distance(SIMD2<Float>(head.x, head.z), SIMD2<Float>(spot.x, spot.z)) < Self.arriveRadius { break }
        }
        live.removeAll { $0 === marker }
        ctx.micro.dissolve(marker)
        guard !Task.isCancelled else { return nil }
        // Settle a beat so the reach starts from a still stance.
        await ctx.clock.wait(0.4)
        head = ctx.tracker.head().columns.3
        return Rig(origin: [head.x, 0, head.z], yaw: yaw, eye: head.y)
    }

    /// Freeze while the creature passes. Samples head and the hand nearest the cube every frame.
    private func hold(cube: SIMD3<Float>, rig: Rig) async -> ReachGrabTrial.Freeze? {
        let creature = Self.makeCreature()
        let from = rig.world([-1.9, rig.eye - 0.1, -2.3]), to = rig.world([1.9, rig.eye - 0.1, -2.3])
        creature.position = from
        creature.orientation = simd_quatf(angle: rig.yaw, axis: [0, 1, 0])
        ctx.layer.addChild(creature)
        live.append(creature)
        Tone.play(.creature, on: creature, gain: -6)
        ctx.cheer("Freeze!", hold: Self.creatureTime)

        let hand = ctx.nearestTip(to: cube)?.hand ?? ctx.dominant
        _ = await ctx.clock.next()
        let start = ctx.now
        let h0 = ctx.tracker.head().columns.3
        var head: [V3] = [], tips: [V3] = []
        var shift: Float = 0
        while ctx.now - start < Self.creatureTime, !Task.isCancelled {
            _ = await ctx.clock.next()
            let q = Float((ctx.now - start) / Self.creatureTime)
            creature.position = from + (to - from) * q + [0, 0.06 * sin(q * 12), 0]
            let h = ctx.tracker.head().columns.3
            head.append(SIMD3<Float>(h.x, h.y, h.z).v3)
            shift = max(shift, simd_distance(SIMD3<Float>(h.x, h.y, h.z), SIMD3<Float>(h0.x, h0.y, h0.z)))
            if let s = ctx.tracker.state(hand) { tips.append(s.indexTip.v3) }
        }
        let end = ctx.now
        live.removeAll { $0 === creature }
        ctx.micro.dissolve(creature)
        guard !Task.isCancelled else { return nil }
        ctx.cheer("Go!", hold: 0.6)
        let shiftCm = Double(shift) * 100
        return ReachGrabTrial.Freeze(startT: start, endT: end, headSwayCmS: Self.pathRate(head, end - start),
                                     handDriftCm: Self.rms(tips).map { $0 * 100 }, headShiftCm: shiftCm,
                                     held: shiftCm <= ReachGrabMetrics.freezeBreakCm,
                                     trackingGapMs: ctx.tracker.buffer.maxGapMs(hand, start, end))
    }

    /// Horizontal head travel from where the participant stood when the cube appeared, meters.
    private func lean(from rig: Rig) -> Double {
        let head = ctx.tracker.head().columns.3
        let dx = head.x - rig.origin.x, dz = head.z - rig.origin.z
        return Double((dx * dx + dz * dz).squareRoot())
    }

    /// Path length over duration, cm/s.
    private static func pathRate(_ p: [V3], _ seconds: Double) -> Double {
        guard p.count > 1, seconds > 0 else { return 0 }
        var path = 0.0
        for k in 1..<p.count { path += p[k].distance(to: p[k - 1]) }
        return path / seconds * 100
    }

    /// RMS distance from the points' own mean, meters. Nil under two points.
    private static func rms(_ points: [V3]) -> Double? {
        guard points.count > 1 else { return nil }
        let mean = points.reduce(V3.zero) { $0 + $1 } / Double(points.count)
        return (points.reduce(0.0) { $0 + ($1 - mean).dot($1 - mean) } / Double(points.count)).squareRoot()
    }

    private static func makeCube() -> ModelEntity {
        let s = Self.size
        let e = ModelEntity(mesh: .generateBox(width: s, height: s, depth: s, cornerRadius: s * 0.12),
                            materials: [Look.glow(Theme.gold)])
        e.components.set(OpacityComponent(opacity: 1))
        return e
    }

    /// Floor spot: a gold ring and a faint disc, flat on the floor.
    private static func makeSpot() -> Entity {
        let root = Entity()
        root.components.set(OpacityComponent(opacity: 1))
        if let mesh = Meshes.ring(radius: arriveRadius, thickness: 0.01, segments: 64, sides: 6) {
            let ring = ModelEntity(mesh: mesh, materials: [Look.glow(Theme.gold, intensity: 1.5)])
            ring.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            root.addChild(ring)
        }
        let disc = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: arriveRadius),
                               materials: [Look.flat(Theme.gold.withAlphaComponent(0.25))])
        root.addChild(disc)
        return root
    }

    /// A round purple creature with big eyes. Friendly, but it means freeze.
    private static func makeCreature() -> Entity {
        let root = Entity()
        root.components.set(OpacityComponent(opacity: 1))
        let body = ModelEntity(mesh: .generateSphere(radius: 0.28), materials: [Look.glow(Theme.creature, intensity: 0.4)])
        root.addChild(body)
        for x: Float in [-0.1, 0.1] {
            let eye = ModelEntity(mesh: .generateSphere(radius: 0.065), materials: [Look.flat(Theme.paper)])
            eye.position = [x, 0.07, 0.24]
            let pupil = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [Look.flat(Theme.ink)])
            pupil.position = [0, 0, 0.045]
            eye.addChild(pupil)
            root.addChild(eye)
        }
        return root
    }
}
