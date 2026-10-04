import RealityKit
import ScoreKit
import simd
import UIKit

/// Color Dots. Some dots light up around you, then every dot turns grey beside decoys. Touch only the ones that lit.
/// The dots spread wider than the field of view, so recall needs head turns. Spec: specs/games/color-dots.md.
@MainActor
final class ColorDotsGame: Minigame {
    static let game = Game.dots
    /// Decoys per trial. Dots in the scene = set size + decoys.
    static let decoys = 4
    static let practiceSet = 2, startSet = 3, minSet = 2, maxSet = 8
    static let radius = Theme.Size.orb
    /// Dot centers sit at least this far apart.
    static let minGap: Float = 0.15
    static let azimuth: ClosedRange<Double> = -100...100
    static let elevation: ClosedRange<Double> = -10...20
    static let reach: ClosedRange<Float> = 0.45...0.55
    /// Study shows for base + per dot x lit dots, in seconds. Recall allows the same kind of sum.
    static let studyBase = 1.5, studyPerDot = 0.5
    static let recallBase = 6.0, recallPerDot = 1.5
    static let maxFalseTaps = 2
    static let pause = 0.8
    /// Emissive intensity of a lit dot, a dim decoy in study, and every dot in recall. Recall matches where
    /// `Micro.glow` starts, so the proximity glow rises from it without a jump.
    static let litGlow: Float = 3, dimGlow: Float = 0.15, recallGlow: Float = 0.6
    static let layoutTries = 20, slotTries = 60

    /// Where one dot sits and the azimuth that put it there.
    private struct Spot {
        let azimuth: Double
        let position: SIMD3<Float>
    }

    let ctx: GameContext
    private var dots: [ModelEntity] = []
    /// Dot centers in world space, so contact never reads a position that a tween is moving.
    private var centers: [SIMD3<Float>] = []

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        var out: [ColorDotsTrial] = []
        var setSize = familiarization ? Self.practiceSet : Self.startSet
        for i in 0..<max(trials, 0) where !Task.isCancelled {
            let (spots, shown) = arrange(setSize: setSize, rng: &rng)
            guard let trial = await run(index: i, setSize: setSize, spots: spots, shown: shown) else { break }
            out.append(trial)
            ctx.hud.done = i + 1
            setSize = Self.nextSet(after: setSize, perfect: trial.hits == setSize && trial.falseTaps == 0)
            await ctx.clock.wait(Self.pause)
        }
        return Block(task: .colorDots, familiarization: familiarization, seed: seed, trials: out.map(Trial.colorDots))
    }

    func teardown() { clear() }

    /// Staircase: one up after a perfect trial, one down after any other.
    static func nextSet(after setSize: Int, perfect: Bool) -> Int {
        perfect ? min(setSize + 1, maxSet) : max(setSize - 1, minSet)
    }

    /// Places set size + decoys dots and picks which of them light.
    private func arrange(setSize: Int, rng: inout SeededRNG) -> (spots: [Spot], shown: [Bool]) {
        let count = setSize + Self.decoys
        let spots = layout(count: count, rng: &rng)
        var ids = Array(0..<count)
        ids.shuffle(using: &rng)
        var shown = Array(repeating: false, count: count)
        for id in ids.prefix(setSize) { shown[id] = true }
        return (spots, shown)
    }

    /// One dot per azimuth slot from -100 to +100 degrees, jittered inside its slot, at a random elevation and
    /// reach, at least 15 cm from every other dot. Slots keep the arc evenly covered at every set size.
    private func layout(count: Int, rng: inout SeededRNG) -> [Spot] {
        let lo = Self.azimuth.lowerBound, hi = Self.azimuth.upperBound
        let step = (hi - lo) / Double(max(count - 1, 1))
        for _ in 0..<Self.layoutTries {
            var spots: [Spot] = []
            for slot in 0..<count {
                let center = lo + step * Double(slot)
                var pick: Spot?
                for _ in 0..<Self.slotTries where pick == nil {
                    let az = Double.random(in: max(center - 0.3 * step, lo)...min(center + 0.3 * step, hi), using: &rng)
                    let p = ctx.reachPoint(azimuthDeg: az, elevationDeg: .random(in: Self.elevation, using: &rng),
                                           reach: .random(in: Self.reach, using: &rng))
                    if spots.allSatisfy({ simd_distance($0.position, p) >= Self.minGap }) {
                        pick = Spot(azimuth: az, position: p)
                    }
                }
                guard let spot = pick else { break }
                spots.append(spot)
            }
            if spots.count == count { return spots }
        }
        return zigzag(count: count)
    }

    /// Fallback: two staggered rows 20 degrees apart at one reach. Neighbors are over 20 cm apart, so it cannot fail.
    private func zigzag(count: Int) -> [Spot] {
        let lo = Self.azimuth.lowerBound
        let step = (Self.azimuth.upperBound - lo) / Double(max(count - 1, 1))
        return (0..<count).map { slot in
            let az = lo + step * Double(slot)
            return Spot(azimuth: az, position: ctx.reachPoint(azimuthDeg: az, elevationDeg: slot % 2 == 0 ? 15 : -5,
                                                              reach: 0.5))
        }
    }

    /// One trial: study, grey out, recall. Nil if the run is cancelled before the trial finishes.
    private func run(index: Int, setSize: Int, spots: [Spot], shown: [Bool]) async -> ColorDotsTrial? {
        centers = spots.map(\.position)
        dots = spots.indices.map { i -> ModelEntity in
            let dot = Micro.orb(shown[i] ? Theme.go : Theme.mute, radius: Self.radius)
            tint(dot, shown[i] ? Theme.go : Theme.mute, intensity: shown[i] ? Self.litGlow : Self.dimGlow)
            dot.position = centers[i]
            ctx.layer.addChild(dot)
            ctx.micro.appear(dot)
            return dot
        }

        // Study. The first frame the dots are in the scene starts the clock, as spawn time does elsewhere.
        _ = await ctx.clock.next()
        let studyStart = ctx.now
        for (rank, i) in dots.indices.filter({ shown[$0] }).enumerated() {
            Tone.play(.star(rank), on: dots[i], gain: -16)
        }
        await ctx.clock.wait(Self.studyBase + Self.studyPerDot * Double(setSize))
        guard !Task.isCancelled else { clear(); return nil }

        // Recall. Every dot goes grey together. The first frame of the grey scene starts the clock.
        for dot in dots { tint(dot, Theme.mute, intensity: Self.recallGlow) }
        _ = await ctx.clock.next()
        let recallStart = ctx.now

        var done = Array(repeating: false, count: dots.count)
        var glowing = done
        var touched: [Int] = [], touchT: [Double] = []
        var hits = 0, falseTaps = 0
        var maxTurn = 0.0, lastT = recallStart
        let limit = Self.recallBase + Self.recallPerDot * Double(setSize)
        while touched.count < setSize, falseTaps < Self.maxFalseTaps, ctx.now - recallStart < limit, !Task.isCancelled {
            _ = await ctx.clock.next()
            let t = ctx.now - recallStart
            if let turn = headTurnDeg() { maxTurn = max(maxTurn, turn) }
            for i in dots.indices where !done[i] {
                // Two hands can land in one frame. Stop at the cap.
                guard touched.count < setSize, falseTaps < Self.maxFalseTaps else { break }
                ctx.micro.breathe(dots[i], t: t)
                let tip = ctx.nearestTip(to: centers[i])
                let d = tip?.distance ?? .infinity
                // Glow only near a fingertip and settle once it leaves, so far dots cost nothing per frame.
                if d < Theme.Motion.glowRange {
                    ctx.micro.glow(dots[i], color: Theme.mute, distance: d)
                    glowing[i] = true
                } else if glowing[i] {
                    tint(dots[i], Theme.mute, intensity: Self.recallGlow)
                    glowing[i] = false
                }
                guard let near = tip, d <= Self.radius + ReachTrial.contactSlack else { continue }
                done[i] = true
                // Hand sample time, kept in order and never before the grey scene began.
                let at = max(ctx.tracker.state(near.hand)?.t ?? ctx.now, lastT)
                touched.append(i)
                touchT.append(at)
                if shown[i] {
                    hits += 1
                    tint(dots[i], Theme.paper, intensity: 3.5)
                    ctx.micro.pop(dots[i], color: Theme.paper, speedStep: Micro.speedStep(reachTime: at - lastT))
                } else {
                    falseTaps += 1
                    flash(dots[i])
                }
                lastT = at
            }
        }
        guard !Task.isCancelled else { clear(); return nil }

        let end = ctx.now
        let buffer = ctx.tracker.buffer
        // Best-tracked hand, as in the reach games: a head turn can take one hand out of view.
        let gap = buffer.maxGapMs(nil, recallStart, end)
        dismiss(done: done, shown: shown)
        return ColorDotsTrial(index: index, setSize: setSize, dotAzimuthDeg: spots.map(\.azimuth),
                              dotPositions: spots.map { $0.position.v3 }, shown: shown, touched: touched,
                              touchT: touchT, studyStartT: studyStart, recallStartT: recallStart, endT: end,
                              hits: hits, falseTaps: falseTaps, misses: setSize - hits, maxHeadTurnDeg: maxTurn,
                              trackingGapMs: gap)
    }

    private func tint(_ dot: ModelEntity, _ color: UIColor, intensity: Float) {
        dot.model?.materials = [Look.glow(color, intensity: intensity)]
    }

    /// Decoy touched: flashes orange for 150 ms, then sinks quietly.
    private func flash(_ dot: ModelEntity) {
        tint(dot, Theme.nogo, intensity: 3.5)
        dot.scale = .init(repeating: 1.2)
        Tone.play(.miss, on: dot, gain: -18)
        let micro = ctx.micro
        ctx.clock.animate(0.15, { _ in }, done: { dot.scale = .one; micro.sink(dot, sound: false) })
    }

    /// End of a trial. Lit dots nobody found sink with one soft tone for the lot, untouched decoys dissolve.
    private func dismiss(done: [Bool], shown: [Bool]) {
        var first = true
        for i in dots.indices where !done[i] {
            if shown[i] {
                ctx.micro.sink(dots[i], sound: first)
                first = false
            } else {
                ctx.micro.dissolve(dots[i])
            }
        }
        dots = []
        centers = []
    }

    private func clear() {
        dots.forEach { $0.removeFromParent() }
        dots = []
        centers = []
    }

    /// Head yaw away from where the game began, degrees, from the head's forward vector flattened onto the floor
    /// (the projection `Rig.init` uses). Nil while the head faces straight up or down.
    private func headTurnDeg() -> Double? {
        let head = ctx.tracker.head()
        let f = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
        guard simd_length(f) > 1e-3 else { return nil }
        var turn = atan2(-f.x, -f.z) - ctx.rig.yaw
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        return Double(abs(turn)) * 180 / .pi
    }
}
