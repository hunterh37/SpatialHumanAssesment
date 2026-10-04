import RealityKit
import ScoreKit
import simd

/// Gate. Blue and orange appear together; touch blue, leave orange. Orange alone: leave it.
/// Spec: specs/games/gate.md.
@MainActor
struct GateGame: Minigame {
    static let game = Game.gate
    static let window = 2.0
    static let goShare = 0.7
    /// Blue and orange sit at least this far apart.
    static let minSeparation: Float = 0.25
    let ctx: GameContext
    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        let ecc = ReachTrial.bins(trials, rng: &rng)
        // Exact 70/30 split, shuffled, so every block has the same go/no-go load.
        var kinds = (0..<trials).map { Double($0) < Double(trials) * Self.goShare ? ReactionTrial.Kind.go : .nogo }
        kinds.shuffle(using: &rng)

        var out: [Trial] = []
        for i in 0..<trials where !Task.isCancelled {
            await ctx.clock.wait(Double.random(in: 0.8...2.0, using: &rng))
            let side: Double = Bool.random(using: &rng) ? 1 : -1
            let el = Double.random(in: -15...20, using: &rng)
            let reach = Float.random(in: 0.38...0.6, using: &rng)
            let first = ctx.reachPoint(azimuthDeg: side * ecc[i], elevationDeg: el, reach: reach)
            // Partner on the other side of the first, 30 to 50 degrees away.
            var second = first
            for _ in 0..<8 {
                let delta = Double.random(in: 30...50, using: &rng) * -side
                second = ctx.reachPoint(azimuthDeg: side * ecc[i] + delta, elevationDeg: .random(in: -15...20, using: &rng),
                                        reach: .random(in: 0.38...0.6, using: &rng))
                if simd_distance(first, second) >= Self.minSeparation { break }
            }
            let trial: ReactionTrial
            if kinds[i] == .go {
                trial = await ReachTrial(ctx: ctx).run(index: i, kind: .go, go: first, nogo: second, window: Self.window)
            } else {
                trial = await ReachTrial(ctx: ctx).run(index: i, kind: .nogo, go: nil, nogo: first, window: Self.window)
            }
            out.append(.reaction(trial))
            ctx.hud.done = i + 1
        }
        return Block(task: .choiceRT, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() {}
}
