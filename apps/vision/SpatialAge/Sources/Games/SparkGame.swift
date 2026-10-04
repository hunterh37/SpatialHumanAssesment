import RealityKit
import ScoreKit
import simd

/// Spatial Tracking (task `simple_rt`). Forest clearing. A rustle from one direction, a flash of light there, or
/// both, says a leaf is coming; the leaf drops from that spot and drifts down. Find it and touch it (punch or
/// point) before it lands. Directions run past the field of view, so the cue has to be located first.
/// Spec: specs/games/spark.md (Games Ideas deck, "Spatial Tracking").
@MainActor
final class SparkGame: Minigame {
    static let game = Game.spark
    /// The leaf appears this long after cue onset, at the cue spot. Spawn time in the log is the cue onset.
    static let lead = 0.35
    /// Fall speed, m/s, and side-to-side drift amplitude, meters.
    static let fallSpeed: Float = 0.38
    static let drift: Float = 0.05
    static let start: Float = 0.45
    static let radius: Float = 0.07
    static let cues = ["audio", "light", "both"]

    let ctx: GameContext
    private var scenery: Entity?
    private var live: [Entity] = []

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        if scenery == nil {
            let f = Scenery.forest(rig: ctx.rig)
            ctx.layer.addChild(f)
            scenery = f
        }
        let ecc = ReachTrial.bins(trials, rng: &rng)
        // Cue kinds balanced and shuffled. Practice uses both, the easiest.
        var cueOrder = (0..<trials).map { Self.cues[$0 % Self.cues.count] }
        cueOrder.shuffle(using: &rng)
        var out: [Trial] = []
        for i in 0..<trials where !Task.isCancelled {
            await ctx.clock.wait(Double.random(in: 1.2...2.6, using: &rng))
            let side: Double = Bool.random(using: &rng) ? 1 : -1
            let az = side * ecc[i]
            let reach = Float.random(in: 0.42...0.58, using: &rng)
            guard let trial = await run(index: i, azimuthDeg: az, reach: reach,
                                        cue: familiarization ? "both" : cueOrder[i], phase: .random(in: 0...6, using: &rng))
            else { break }
            out.append(.reaction(trial))
            ctx.hud.done = i + 1
        }
        return Block(task: .simpleRT, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() {
        live.forEach { $0.removeFromParent() }
        live = []
        scenery?.removeFromParent(); scenery = nil
    }

    private func run(index: Int, azimuthDeg: Double, reach: Float, cue: String, phase: Float) async -> ReactionTrial? {
        // Column the leaf falls down: around the dominant shoulder at `azimuthDeg`, starting above the eyes.
        let column = ctx.reachPoint(azimuthDeg: azimuthDeg, elevationDeg: 0, reach: reach)
        let top = SIMD3<Float>(column.x, ctx.rig.eye + Self.start, column.z)
        let lateral = simd_normalize(simd_cross([0, 1, 0], top - ctx.rig.origin))

        // Cue. Sound plays from the spot; light is a soft flare there. Either starts the clock.
        let anchor = Entity()
        anchor.position = top
        ctx.layer.addChild(anchor)
        live.append(anchor)
        _ = await ctx.clock.next()
        let spawn = ctx.now
        if cue != "light" { Tone.play(.rustle, on: anchor, gain: -4) }
        if cue != "audio" { flare(at: top) }
        let ecc = ctx.eccentricity(of: top)
        await ctx.clock.wait(Self.lead)
        guard !Task.isCancelled else { return nil }

        let leaf = Scenery.leaf(Theme.gold)
        leaf.position = top
        ctx.layer.addChild(leaf)
        live.append(leaf)
        ctx.micro.appear(leaf)
        let shown = ctx.now
        let half: Float = 0.055

        var touched: (Hand, Double, SIMD3<Float>, SIMD3<Float>)?
        var center = top - [0, half, 0]
        while touched == nil, !Task.isCancelled {
            _ = await ctx.clock.next()
            let t = Float(ctx.now - shown)
            let stem = top + [0, -Self.fallSpeed * t, 0] + lateral * (Self.drift * sin(2.4 * t + phase))
            if stem.y - 2 * half < 0.01 { break }
            leaf.position = stem
            leaf.orientation = simd_quatf(angle: 0.5 * sin(1.7 * t + phase), axis: [0, 0, 1])
                * simd_quatf(angle: atan2(ctx.rig.origin.x - stem.x, ctx.rig.origin.z - stem.z), axis: [0, 1, 0])
            center = stem - [0, half, 0]
            guard let near = ctx.nearestTip(to: center) else { continue }
            ctx.micro.glow(leaf, color: Theme.gold, distance: near.distance)
            if near.distance <= Self.radius + ReachTrial.contactSlack {
                touched = (near.hand, ctx.tracker.state(near.hand)?.t ?? ctx.now, near.tip, center)
            }
        }
        live.removeAll { $0 === leaf || $0 === anchor }
        anchor.removeFromParent()
        guard !Task.isCancelled else { leaf.removeFromParent(); return nil }

        guard let (hand, tContact, tip, at) = touched else {
            ctx.micro.sink(leaf)
            let gap = ctx.tracker.buffer.maxGapMs(nil, spawn, ctx.now)
            return ReactionTrial(index: index, kind: .go, hand: nil, spawnT: spawn, moveT: nil, contactT: nil,
                                 position: column.v3, eccentricityDeg: ecc, outcome: .miss, trackingGapMs: gap, cue: cue)
        }
        let trace = ctx.tracker.buffer.trace(hand, spawn - ReachTrial.preRoll, tContact)
        let moveT = Kinematics(trace)?.onset(after: spawn, before: tContact)
        ctx.micro.pop(leaf, color: Theme.paper, speedStep: Micro.speedStep(reachTime: tContact - spawn - Self.lead))
        ctx.cheer()
        return ReactionTrial(index: index, kind: .go, hand: hand, spawnT: spawn, moveT: moveT, contactT: tContact,
                             position: at.v3, eccentricityDeg: ecc, outcome: .hit,
                             trackingGapMs: ctx.tracker.buffer.maxGapMs(hand, spawn, tContact),
                             endpointErrorM: Double(simd_distance(tip, at)), trace: trace, cue: cue)
    }

    /// Light cue: a soft sphere at the spot swells and fades over 0.5 s.
    private func flare(at p: SIMD3<Float>) {
        let glow = Micro.orb(Theme.paper, radius: 0.09)
        glow.model?.materials = [Look.glow(Theme.paper, intensity: 4)]
        glow.position = p
        ctx.layer.addChild(glow)
        ctx.clock.animate(0.5, { q in
            glow.scale = .init(repeating: Float(0.4 + 1.2 * Ease.out(q)))
            glow.components[OpacityComponent.self]?.opacity = Float(1 - q)
        }, done: { glow.removeFromParent() })
    }
}
