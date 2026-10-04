import RealityKit
import ScoreKit

/// Runs the queued minigames in order: intro, familiarization, scored block, next game.
@MainActor
final class Director {
    let ctx: GameContext

    init(ctx: GameContext) { self.ctx = ctx }

    static func make(_ game: Game, _ ctx: GameContext) -> any Minigame {
        switch game {
        case .pendulum: PendulumGame(ctx)
        case .spark: SparkGame(ctx)
        case .gate: GateGame(ctx)
        case .constellation: ConstellationGame(ctx)
        case .orbit: OrbitGame(ctx)
        case .reach: ReachGrabGame(ctx)
        case .wall: WallGame(ctx)
        case .dots: ColorDotsGame(ctx)
        }
    }

    func run(_ games: [Game]) async {
        var seeds = SeededRNG(seed: Int(ctx.recorder.start * 1000))
        for (index, game) in games.enumerated() where !Task.isCancelled {
            ctx.recenter()
            ctx.hud.step = games.count > 1 ? "\(index + 1) / \(games.count)" : ""
            let instance = Self.make(game, ctx)
            for familiarization in [true, false] {
                let n = familiarization ? game.familiarizationTrials : game.scoredTrials
                ctx.show(game, familiarization: familiarization, total: n)
                await ctx.clock.wait(familiarization ? 2.5 : 1.8)
                await ctx.countdown()
                let seed = Int(truncatingIfNeeded: seeds.next() >> 33)
                let block = await instance.play(familiarization: familiarization, trials: n, seed: seed)
                ctx.recorder.append(block)
                ctx.cheer(familiarization ? "Practice done. Nice work!" : "Great job!", hold: 1.4)
                await ctx.clock.wait(1.4)
            }
            instance.teardown()
            ctx.hud.visible = false
            await ctx.clock.wait(1.0)
        }
    }
}
