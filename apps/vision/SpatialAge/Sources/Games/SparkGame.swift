import RealityKit
import ScoreKit

/// Spark. One blue light appears within reach; touch it. Spec: specs/games/spark.md.
@MainActor
struct SparkGame: Minigame {
    static let game = Game.spark
    static let window = 3.0
    let ctx: GameContext
    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        let ecc = ReachTrial.bins(trials, rng: &rng)
        var out: [Trial] = []
        for i in 0..<trials where !Task.isCancelled {
            await ctx.clock.wait(Double.random(in: 0.8...2.0, using: &rng))
            let side: Double = Bool.random(using: &rng) ? 1 : -1
            let p = ctx.reachPoint(azimuthDeg: side * ecc[i], elevationDeg: .random(in: -15...20, using: &rng),
                                   reach: .random(in: 0.35...0.65, using: &rng))
            let trial = await ReachTrial(ctx: ctx).run(index: i, kind: .go, go: p, nogo: nil, window: Self.window)
            out.append(.reaction(trial))
            ctx.hud.done = i + 1
        }
        return Block(task: .simpleRT, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() {}
}
