import Foundation
import RealityKit
import ScoreKit
import simd

/// Hole in the Wall. The participant stands on a stone island ringed by a moat. A wall with a body-shaped
/// cut-out glides across the water toward them; they make the shape (both hands in the hand holes) and hold it
/// until the wall reaches the island. Spec: specs/games/wall.md (Games Ideas deck, "Hole in the Wall").
///
/// The wall moves along the forward axis of the participant frame (origin on the floor under the head at
/// game start, -z forward), so the logged cutout centers are exactly where the holes stop. Head and hands
/// are sampled every frame of the hold window and nowhere else.
@MainActor
final class WallGame: Minigame {
    static let game = Game.wall
    /// Wall plane, rig-local z. It starts 3 m out and stops 0.30 m ahead, or 0.55 m for the forward pose.
    static let startZ: Float = -3.0
    static let arriveZ: Float = -0.30
    static let forwardArriveZ: Float = -0.55
    /// Seconds after the first frame of motion. The hold is the last 1.5 s of the approach.
    static let holdAt = 3.5
    static let duration = 5.0
    /// The wall hangs at the far end this long before it moves, so the pose can be read.
    static let preview = 0.6
    static let pause = 1.0
    static let wallWidth: Float = 1.6
    static let wallHeight: Float = 2.0
    static let panelOpacity: Float = 0.7
    /// Pale rim around the cut-out silhouette, meters.
    static let rimWidth: Float = 0.012
    static let holeRadius: Float = 0.10
    static let ringTube: Float = 0.010

    /// Where the two hands go. Cutout centers are rig-local (x right, y up from the floor) in the wall plane.
    enum Pose: String, CaseIterable {
        case armsOut = "arms_out", armsUp = "arms_up", reachLeft = "reach_left", reachRight = "reach_right"
        case highLow = "high_low", forward

        /// Left and right cutout centers for a participant whose eyes are `e` above the floor.
        /// Shoulders sit 25 cm lower, the estimate `GameContext.shoulder` uses.
        func cutouts(eye e: Float) -> (left: SIMD2<Float>, right: SIMD2<Float>) {
            let sh = e - 0.25
            switch self {
            case .armsOut: return (SIMD2<Float>(-0.55, sh), SIMD2<Float>(0.55, sh))
            case .armsUp: return (SIMD2<Float>(-0.20, e + 0.30), SIMD2<Float>(0.20, e + 0.30))
            case .reachLeft: return (SIMD2<Float>(-0.65, sh + 0.05), SIMD2<Float>(-0.25, sh + 0.05))
            case .reachRight: return (SIMD2<Float>(0.25, sh + 0.05), SIMD2<Float>(0.65, sh + 0.05))
            case .highLow: return (SIMD2<Float>(-0.35, e + 0.20), SIMD2<Float>(0.40, sh - 0.35))
            case .forward: return (SIMD2<Float>(-0.15, sh), SIMD2<Float>(0.15, sh))
            }
        }
    }

    /// One hand point and the tracker time it was sampled.
    private struct Sample {
        let t: Double
        let p: V3
    }

    let ctx: GameContext
    private var current: Entity?
    private var scenery: Entity?

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        // Re-anchor after the intro and countdown, so the island is under the participant where they now
        // stand, and the walls come straight at them.
        await ctx.recenter()
        scenery?.removeFromParent()
        let moat = Scenery.moat(rig: ctx.rig)
        ctx.layer.addChild(moat)
        scenery = moat
        // One shuffle of the six poses, cycled, so every pose appears before any repeats.
        let cycle = Pose.allCases.shuffled(using: &rng)
        var out: [WallTrial] = []
        for i in 0..<trials where !Task.isCancelled {
            var pose = familiarization ? Pose.armsOut : cycle[i % cycle.count]
            #if DEBUG
            if let p = ProcessInfo.processInfo.environment["SA_WALL_POSE"].flatMap(Pose.init) { pose = p }
            #endif
            guard let trial = await run(index: i, pose: pose) else { break }
            out.append(trial)
            ctx.hud.done = i + 1
            await ctx.clock.wait(Self.pause)
        }
        return Block(task: .wall, familiarization: familiarization, seed: seed, trials: out.map(Trial.wall))
    }

    func teardown() {
        current?.removeFromParent(); current = nil
        scenery?.removeFromParent(); scenery = nil
    }

    /// Plays one wall. Nil if the run is cancelled before the wall arrives.
    private func run(index: Int, pose: Pose) async -> WallTrial? {
        let rig = ctx.rig
        let (l, r) = pose.cutouts(eye: rig.eye)
        let stopZ = Self.arrivalZ(pose)
        // Where the holes stop, world space. Hands are scored against these, not against the moving holes.
        let leftTarget = rig.world([l.x, l.y, stopZ]), rightTarget = rig.world([r.x, r.y, stopZ])
        let targets = [leftTarget, rightTarget]

        let (wall, panel, rings) = makeWall(rig: rig, cutouts: [l, r], eye: rig.eye)
        current = wall
        ctx.layer.addChild(wall)
        ctx.micro.appear(wall)
        #if DEBUG
        // Screenshot hook: SA_WALL_FREEZE=<z> holds the wall at rig-local z for good.
        if let z = ProcessInfo.processInfo.environment["SA_WALL_FREEZE"].flatMap(Float.init) {
            wall.position = rig.world([0, 0, z])
            while !Task.isCancelled { _ = await ctx.clock.next() }
            return nil
        }
        #endif

        // The wall hangs at the far end for a moment, rings breathing, so the pose can be read.
        var life = 0.0
        while life < Self.preview, !Task.isCancelled {
            life += await ctx.clock.next()
            breathe(rings, t: life)
            glow(rings, targets)
        }

        // Start time: the first frame of motion.
        _ = await ctx.clock.next()
        let startT = ctx.now
        let holdStartT = startT + Self.holdAt, passT = startT + Self.duration

        var head: [V3] = [], headT: [Double] = []
        var samples: [Hand: [Sample]] = [.left: [], .right: []]
        var lastStamp: [Hand: Double] = [:]
        while !Task.isCancelled {
            life += await ctx.clock.next()
            let t = ctx.now - startT
            let progress = Float(min(max(t / Self.duration, 0), 1))
            wall.position = rig.world([0, 0, Self.startZ + (stopZ - Self.startZ) * progress])
            // The rings breathe while the wall approaches and go still when the hold begins.
            if t < Self.holdAt { breathe(rings, t: life) } else { rings.forEach { $0.scale = .one } }
            glow(rings, targets)

            if t >= Self.holdAt, t <= Self.duration {
                let h = ctx.tracker.head().columns.3
                head.append(SIMD3<Float>(h.x, h.y, h.z).v3)
                headT.append(ctx.now)
                for (hand, s) in ctx.tracker.trackedHands {
                    // One point per tracker sample, inside the window: a stale sample is not counted twice.
                    guard s.t >= holdStartT, s.t <= passT, s.t > (lastStamp[hand] ?? -1) else { continue }
                    lastStamp[hand] = s.t
                    samples[hand, default: []].append(Sample(t: s.t, p: Self.handPoint(s).v3))
                }
            }
            if t >= Self.duration { break }
        }
        guard !Task.isCancelled else {
            wall.removeFromParent(); current = nil
            return nil
        }

        // Clear rule: over the last 0.5 s both hands average within 12 cm of their targets.
        // A hand with no samples there cannot be in its hole, so the wall is a hit.
        let leftS = samples[.left] ?? [], rightS = samples[.right] ?? []
        let tailFrom = passT - WallMetrics.clearWindowS
        let leftTail = Self.meanDistance(leftS.filter { $0.t >= tailFrom }, to: leftTarget.v3)
        let rightTail = Self.meanDistance(rightS.filter { $0.t >= tailFrom }, to: rightTarget.v3)
        let cleared = [leftTail, rightTail].allSatisfy { ($0 ?? Double.infinity) <= WallMetrics.clearRadiusM }

        let drifts = [leftS, rightS].compactMap { Self.rms($0.map { $0.p }) }
        let gap = max(ctx.tracker.buffer.maxGapMs(.left, holdStartT, passT),
                      ctx.tracker.buffer.maxGapMs(.right, holdStartT, passT))
        let trial = WallTrial(index: index, pose: pose.rawValue, startT: startT, holdStartT: holdStartT, passT: passT,
                              leftTarget: leftTarget.v3, rightTarget: rightTarget.v3,
                              leftErrorM: Self.meanDistance(leftS, to: leftTarget.v3),
                              rightErrorM: Self.meanDistance(rightS, to: rightTarget.v3),
                              headSwayCmS: Self.swayCmS(head, headT),
                              handDriftCm: Stats.mean(drifts).map { $0 * 100 },
                              outcome: cleared ? .cleared : .hit, trackingGapMs: gap)

        await feedback(cleared: cleared, panel: panel, rings: rings)
        wall.removeFromParent()
        current = nil
        return trial
    }

    /// Wall root at the far end, standing on the floor with its face toward the participant: one panel and
    /// one ring per cutout. The root sits at floor level, so children use rig-local x and y directly.
    private func makeWall(rig: Rig, cutouts: [SIMD2<Float>], eye: Float) -> (root: Entity, panel: ModelEntity, rings: [ModelEntity]) {
        let root = Entity()
        root.orientation = rig.rotation
        root.position = rig.world([0, 0, Self.startZ])
        // Tall enough that the highest hole keeps 25 cm of wall above its center.
        let height = max(Self.wallHeight, (cutouts.map { $0.y }.max() ?? 0) + Self.holeRadius + 0.25, eye + 0.4)
        let panel = ModelEntity(mesh: .generateBox(width: Self.wallWidth, height: height, depth: 0.02),
                                materials: [Look.flat(Theme.stone)])
        // Just behind the ring plane, so the rings and the cut-out sit on the face.
        panel.position = [0, height / 2, -0.012]
        panel.components.set(OpacityComponent(opacity: Self.panelOpacity))
        root.addChild(panel)
        root.addChild(silhouette(cutouts: cutouts, eye: eye))
        var rings: [ModelEntity] = []
        for c in cutouts {
            let ring = Self.makeRing()
            ring.position = [c.x, c.y, 0]
            root.addChild(ring)
            rings.append(ring)
        }
        return (root, panel, rings)
    }

    /// The body-shaped cut-out, drawn in ink on the wall face with a pale rim: a standing figure whose hands
    /// sit in the two holes (`BodySilhouette`). It reads as a hole because it is the darkest thing on the wall.
    private func silhouette(cutouts: [SIMD2<Float>], eye: Float) -> Entity {
        let root = Entity()
        let sh = eye - 0.25
        // Rim behind, figure in front, both just proud of the panel face (z = -0.002).
        for (inflate, z, color) in [(Self.rimWidth, Float(0.001), Theme.paper.withAlphaComponent(0.85)),
                                    (0, Float(0.002), Theme.ink)] {
            let body = BodySilhouette(eye: eye, shoulderY: sh, left: cutouts[0], right: cutouts[1], inflate: inflate)
            guard let mesh = Meshes.flat(body.pieces, z: z) else { continue }
            root.addChild(ModelEntity(mesh: mesh, materials: [Look.flat(color)]))
        }
        return root
    }

    /// Blue ring that can glow, breathe, pop and sink like a Micro orb. Faces +z, toward the participant.
    private static func makeRing() -> ModelEntity {
        let mesh = Meshes.ring(radius: holeRadius, thickness: ringTube) ?? MeshResource.generateSphere(radius: ringTube * 3)
        let e = ModelEntity(mesh: mesh, materials: [Look.glow(Theme.go)])
        e.components.set(OpacityComponent(opacity: 1))
        return e
    }

    private func breathe(_ rings: [ModelEntity], t: Double) {
        rings.forEach { ctx.micro.breathe($0, t: t) }
    }

    /// Each ring glows with the distance from its own hand to where its hole will stop, so the hand finds the
    /// spot early. It never says when to move.
    private func glow(_ rings: [ModelEntity], _ targets: [SIMD3<Float>]) {
        for (k, hand) in [Hand.left, Hand.right].enumerated() {
            let d = ctx.tracker.state(hand).map { simd_distance(Self.handPoint($0), targets[k]) } ?? Float.infinity
            ctx.micro.glow(rings[k], color: Theme.go, distance: d)
        }
    }

    /// Cleared: both rings pop with a paper ring and the wall fades. Hit: the wall flashes orange and sinks with
    /// the quiet low tone, and the rings take the miss sink.
    private func feedback(cleared: Bool, panel: ModelEntity, rings: [ModelEntity]) async {
        if cleared {
            rings.forEach { ctx.micro.pop($0, color: Theme.paper, speedStep: 3) }
            fade(panel, from: Self.panelOpacity, over: 0.3, drop: false)
        } else {
            panel.model?.materials = [Look.flat(Theme.nogo)]
            fade(panel, from: 0.55, over: 0.4, drop: true)
            // One tone for the whole wall, not one per ring.
            for (k, ring) in rings.enumerated() { ctx.micro.sink(ring, sound: k == 0) }
        }
        await ctx.clock.wait(0.45)
    }

    /// Fades the panel out from `start` opacity. `Micro.dissolve` and `sink` fade from full opacity, which
    /// would flare a panel that rests at 22 percent. `drop` also lowers it 3 cm, like the miss sink.
    private func fade(_ panel: ModelEntity, from start: Float, over seconds: Double, drop: Bool) {
        let y = panel.position.y
        ctx.clock.animate(seconds) { p in
            let q = Float(Ease.out(p))
            panel.components[OpacityComponent.self]?.opacity = start * (1 - q)
            if drop { panel.position.y = y - Theme.Motion.sinkDepth * q }
        }
    }

    /// Rig-local z where the wall plane stops.
    private static func arrivalZ(_ pose: Pose) -> Float { pose == .forward ? forwardArriveZ : arriveZ }

    /// Midpoint of wrist and index fingertip: the middle of the hand, which is what goes in the hole.
    private static func handPoint(_ s: HandTracker.HandState) -> SIMD3<Float> { (s.wrist + s.indexTip) / 2 }

    /// Mean distance from the samples to a point, meters. Nil with no samples.
    private static func meanDistance(_ samples: [Sample], to target: V3) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0.0) { $0 + $1.p.distance(to: target) } / Double(samples.count)
    }

    /// RMS distance of the points from their own mean, meters. Nil under two points, where drift is undefined.
    private static func rms(_ points: [V3]) -> Double? {
        guard points.count > 1 else { return nil }
        let mean = points.reduce(V3.zero) { $0 + $1 } / Double(points.count)
        let sumSquares = points.reduce(0.0) { $0 + ($1 - mean).dot($1 - mean) }
        return (sumSquares / Double(points.count)).squareRoot()
    }

    /// Head 3D path length over the sampled hold divided by its duration, cm/s.
    private static func swayCmS(_ points: [V3], _ times: [Double]) -> Double {
        guard points.count > 1, let first = times.first, let last = times.last, last > first else { return 0 }
        var path = 0.0
        for k in 1..<points.count { path += points[k].distance(to: points[k - 1]) }
        return path / (last - first) * 100
    }
}
