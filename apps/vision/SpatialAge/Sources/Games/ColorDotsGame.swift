import RealityKit
import ScoreKit
import simd
import UIKit

/// Spatial Memory (task `color_dots`). Colored balls of two sizes surround the participant.
/// 1. Select: the HUD names a rule ("Touch every blue ball", "Touch every big ball"); touch the balls that fit it.
/// 2. Every ball turns grey and the same size.
/// 3. Recall: touch every ball you DID touch, or every ball you DID NOT touch, as the HUD says.
/// Recall answers come from what was touched in select, so a select mistake is not punished twice.
/// Spec: specs/games/color-dots.md (Games Ideas deck, "Spatial Memory").
@MainActor
final class ColorDotsGame: Minigame {
    static let game = Game.dots
    /// Rule targets per trial, staircased. Distractors = targets + 2.
    static let practiceSet = 2, startSet = 3, minSet = 2, maxSet = 6
    static let smallRadius: Float = 0.032, bigRadius: Float = 0.052, recallRadius: Float = 0.042
    /// Ball centers sit at least this far apart.
    static let minGap: Float = 0.16
    /// Around the participant, past the shoulders, so finding them takes a turn of the body.
    static let azimuth: ClosedRange<Double> = -135...135
    static let elevation: ClosedRange<Double> = -10...20
    static let reach: ClosedRange<Float> = 0.45...0.55
    static let selectBase = 5.0, selectPerBall = 1.5
    static let recallBase = 6.0, recallPerBall = 1.5
    static let maxFalseTaps = 2
    static let pause = 0.8
    static let recallGlow: Float = 0.6
    static let layoutTries = 20, slotTries = 60

    /// Name and color of each ball color. Names go in the log and the rule.
    static let palette: [(name: String, color: UIColor)] = [
        ("blue", Theme.go), ("orange", Theme.nogo), ("yellow", Theme.gold), ("green", Theme.teal),
    ]

    private struct Spot {
        let azimuth: Double
        let position: SIMD3<Float>
    }

    /// One trial's balls and rule.
    private struct Board {
        var spots: [Spot]
        var colors: [Int]
        var big: [Bool]
        var match: [Bool]
        var rule: String
        var prompt: String
    }

    let ctx: GameContext
    private var balls: [ModelEntity] = []
    private var centers: [SIMD3<Float>] = []

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        var out: [ColorDotsTrial] = []
        var setSize = familiarization ? Self.practiceSet : Self.startSet
        // Recall asks DID and DID NOT equally often. Practice asks DID.
        var modes = (0..<max(trials, 0)).map { $0 % 2 == 0 ? "did" : "didnt" }
        modes.shuffle(using: &rng)
        for i in 0..<max(trials, 0) where !Task.isCancelled {
            let board = arrange(targets: setSize, byColor: i % 2 == 0, rng: &rng)
            let mode = familiarization ? "did" : modes[i]
            guard let trial = await run(index: i, board: board, mode: mode) else { break }
            out.append(trial)
            ctx.hud.done = i + 1
            setSize = Self.nextSet(after: setSize, perfect: trial.hits == trial.setSize && trial.falseTaps == 0)
            await ctx.clock.wait(Self.pause)
        }
        return Block(task: .colorDots, familiarization: familiarization, seed: seed, trials: out.map(Trial.colorDots))
    }

    func teardown() { clear() }

    /// Staircase on rule targets: one up after a perfect recall, one down after any other.
    static func nextSet(after setSize: Int, perfect: Bool) -> Int {
        perfect ? min(setSize + 1, maxSet) : max(setSize - 1, minSet)
    }

    /// Rule by color: targets share one color, distractors take the others, sizes random.
    /// Rule by size: targets are big, distractors small, colors random.
    private func arrange(targets: Int, byColor: Bool, rng: inout SeededRNG) -> Board {
        let count = targets * 2 + 2
        let spots = layout(count: count, rng: &rng)
        var ids = Array(0..<count)
        ids.shuffle(using: &rng)
        var match = Array(repeating: false, count: count)
        for id in ids.prefix(targets) { match[id] = true }
        let key = Int.random(in: 0..<Self.palette.count, using: &rng)
        var colors = [Int](), big = [Bool]()
        for i in 0..<count {
            if byColor {
                colors.append(match[i] ? key : (key + Int.random(in: 1..<Self.palette.count, using: &rng)) % Self.palette.count)
                big.append(Bool.random(using: &rng))
            } else {
                colors.append(Int.random(in: 0..<Self.palette.count, using: &rng))
                big.append(match[i])
            }
        }
        let name = Self.palette[key].name
        return Board(spots: spots, colors: colors, big: big, match: match,
                     rule: byColor ? "color:\(name)" : "size:large",
                     prompt: byColor ? "Touch every \(name) ball." : "Touch every big ball.")
    }

    /// One ball per azimuth slot across the arc, jittered in its slot, at least `minGap` from every other ball.
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
                    let p = point(az: az, el: .random(in: Self.elevation, using: &rng), reach: .random(in: Self.reach, using: &rng))
                    if spots.allSatisfy({ simd_distance($0.position, p) >= Self.minGap }) {
                        pick = Spot(azimuth: az, position: p)
                    }
                }
                guard let spot = pick else { break }
                spots.append(spot)
            }
            if spots.count == count { return spots }
        }
        // Fallback: two staggered rows 20 degrees apart. Neighbors are over 16 cm apart, so it cannot fail.
        return (0..<count).map { slot in
            let az = lo + step * Double(slot)
            return Spot(azimuth: az, position: point(az: az, el: slot % 2 == 0 ? 15 : -5, reach: 0.5))
        }
    }

    /// Around the head rather than the shoulder, so balls behind the participant stay at arm's length after a turn.
    private func point(az: Double, el: Double, reach: Float) -> SIMD3<Float> {
        let a = Float(az * .pi / 180), e = Float(el * .pi / 180)
        let shoulderY = ctx.rig.eye - 0.25
        return ctx.rig.world([sin(a) * cos(e) * reach, shoulderY + sin(e) * reach, -cos(a) * cos(e) * reach])
    }

    /// One trial: select, grey out, recall. Nil if the run is cancelled before the trial finishes.
    private func run(index: Int, board: Board, mode: String) async -> ColorDotsTrial? {
        let n = board.spots.count
        centers = board.spots.map(\.position)
        balls = (0..<n).map { i -> ModelEntity in
            let color = Self.palette[board.colors[i]].color
            let ball = Micro.orb(color, radius: board.big[i] ? Self.bigRadius : Self.smallRadius)
            ball.position = centers[i]
            ctx.layer.addChild(ball)
            ctx.micro.appear(ball)
            return ball
        }
        let base = ctx.hud.line
        ctx.hud.line = board.prompt

        // Select. The first frame the balls are in the scene starts the clock.
        _ = await ctx.clock.next()
        let selectStart = ctx.now
        var picked = Array(repeating: false, count: n)
        var selected: [Int] = [], selectT: [Double] = []
        let targets = board.match.filter { $0 }.count
        var lastT = selectStart
        let selectLimit = Self.selectBase + Self.selectPerBall * Double(targets)
        var maxTurn = 0.0
        while selected.count < targets, ctx.now - selectStart < selectLimit, !Task.isCancelled {
            _ = await ctx.clock.next()
            if let turn = headTurnDeg() { maxTurn = max(maxTurn, turn) }
            for i in 0..<n where !picked[i] {
                guard selected.count < targets else { break }
                let radius = board.big[i] ? Self.bigRadius : Self.smallRadius
                guard let near = ctx.nearestTip(to: centers[i]), near.distance <= radius + ReachTrial.contactSlack
                else { continue }
                picked[i] = true
                let at = max(ctx.tracker.state(near.hand)?.t ?? ctx.now, lastT)
                selected.append(i); selectT.append(at)
                lastT = at
                // Same mark for any pick: a ring and a tick, and the ball stays put. No right or wrong shown.
                ctx.micro.ring(at: centers[i], color: Theme.paper, radius: radius * 2)
                Tone.play(.pop(step: 3), on: balls[i], gain: -14)
            }
        }
        guard !Task.isCancelled else { clear(); return nil }

        // Grey out: every ball the same grey and the same size, so only place is left to remember.
        await ctx.clock.wait(0.6)
        let answers = (0..<n).map { mode == "did" ? picked[$0] : !picked[$0] }
        let setSize = answers.filter { $0 }.count
        for ball in balls {
            ball.model?.mesh = .generateSphere(radius: Self.recallRadius)
            ball.model?.materials = [Look.glow(Theme.mute, intensity: Self.recallGlow)]
        }
        ctx.hud.line = mode == "did" ? "Now touch every ball you DID touch." : "Now touch every ball you DID NOT touch."
        Tone.play(.tock, on: ctx.layer, gain: -14)
        _ = await ctx.clock.next()
        let recallStart = ctx.now

        var done = Array(repeating: false, count: n)
        var glowing = done
        var touched: [Int] = [], touchT: [Double] = []
        var hits = 0, falseTaps = 0
        lastT = recallStart
        let limit = Self.recallBase + Self.recallPerBall * Double(setSize)
        while hits < setSize, falseTaps < Self.maxFalseTaps, ctx.now - recallStart < limit, !Task.isCancelled {
            _ = await ctx.clock.next()
            let t = ctx.now - recallStart
            if let turn = headTurnDeg() { maxTurn = max(maxTurn, turn) }
            for i in 0..<n where !done[i] {
                guard hits < setSize, falseTaps < Self.maxFalseTaps else { break }
                ctx.micro.breathe(balls[i], t: t)
                let tip = ctx.nearestTip(to: centers[i])
                let d = tip?.distance ?? .infinity
                if d < Theme.Motion.glowRange {
                    ctx.micro.glow(balls[i], color: Theme.mute, distance: d)
                    glowing[i] = true
                } else if glowing[i] {
                    balls[i].model?.materials = [Look.glow(Theme.mute, intensity: Self.recallGlow)]
                    glowing[i] = false
                }
                guard let near = tip, d <= Self.recallRadius + ReachTrial.contactSlack else { continue }
                done[i] = true
                let at = max(ctx.tracker.state(near.hand)?.t ?? ctx.now, lastT)
                touched.append(i); touchT.append(at)
                if answers[i] {
                    hits += 1
                    ctx.micro.pop(balls[i], color: Theme.paper, speedStep: Micro.speedStep(reachTime: at - lastT))
                } else {
                    falseTaps += 1
                    flash(balls[i])
                }
                lastT = at
            }
        }
        guard !Task.isCancelled else { clear(); return nil }
        if setSize > 0, hits == setSize, falseTaps == 0 { ctx.cheer() }

        let end = ctx.now
        let gap = ctx.tracker.buffer.maxGapMs(nil, selectStart, end)
        dismiss(done: done, answers: answers)
        ctx.hud.line = base
        return ColorDotsTrial(index: index, setSize: setSize, dotAzimuthDeg: board.spots.map(\.azimuth),
                              dotPositions: board.spots.map { $0.position.v3 }, shown: answers, touched: touched,
                              touchT: touchT, studyStartT: selectStart, recallStartT: recallStart, endT: end,
                              hits: hits, falseTaps: falseTaps, misses: setSize - hits, maxHeadTurnDeg: maxTurn,
                              trackingGapMs: gap, rule: board.rule, ruleMatch: board.match,
                              colors: board.colors.map { Self.palette[$0].name },
                              radii: board.big.map { Double($0 ? Self.bigRadius : Self.smallRadius) },
                              selected: selected, selectT: selectT, recallMode: mode)
    }

    /// Wrong recall touch: flashes orange for 150 ms, then sinks quietly.
    private func flash(_ ball: ModelEntity) {
        ball.model?.materials = [Look.glow(Theme.nogo, intensity: 3.5)]
        ball.scale = .init(repeating: 1.2)
        Tone.play(.miss, on: ball, gain: -18)
        let micro = ctx.micro
        ctx.clock.animate(0.15, { _ in }, done: { ball.scale = .one; micro.sink(ball, sound: false) })
    }

    /// End of a trial. Answers nobody found sink with one soft tone for the lot, the rest dissolve.
    private func dismiss(done: [Bool], answers: [Bool]) {
        var first = true
        for i in balls.indices where !done[i] {
            if answers[i] {
                ctx.micro.sink(balls[i], sound: first)
                first = false
            } else {
                ctx.micro.dissolve(balls[i])
            }
        }
        balls = []
        centers = []
    }

    private func clear() {
        balls.forEach { $0.removeFromParent() }
        balls = []
        centers = []
    }

    /// Head yaw away from where the game began, degrees, from the head's forward vector flattened onto the floor.
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
