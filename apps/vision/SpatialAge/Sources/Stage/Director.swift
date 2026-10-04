import RealityKit
import ScoreKit

/// Runs the queued minigames in order: intro, familiarization, scored block, next game.
@MainActor
final class Director {
    let ctx: GameContext
    /// Run the unscored practice block before each game (Dusk intro toggle "Practice round first").
    let practice: Bool
    /// Called as each game starts, before its intro. The music bed changes track on it.
    let onGame: @MainActor (Game) -> Void

    init(ctx: GameContext, practice: Bool = true, onGame: @escaping @MainActor (Game) -> Void = { _ in }) {
        self.ctx = ctx
        self.practice = practice
        self.onGame = onGame
    }

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
            onGame(game)
            await ctx.recenter()
            ctx.hud.step = games.count > 1 ? "\(index + 1) / \(games.count)" : ""
            let instance = Self.make(game, ctx)
            let blockSeeds = (0..<2).map { _ in Int(truncatingIfNeeded: seeds.next() >> 33) }
            // Each game runs in its own task so the HUD skip control can end it alone. A skipped game
            // records nothing from the block it was in.
            let ctx = ctx, practice = practice
            let current = Task { @MainActor in
                let blocks: [Bool] = practice ? [true, false] : [false]
                for familiarization in blocks where !Task.isCancelled {
                    let k = familiarization ? 0 : 1
                    let n = familiarization ? game.familiarizationTrials : game.scoredTrials
                    ctx.show(game, familiarization: familiarization, total: n)
                    await ctx.clock.wait(familiarization ? 2.5 : 1.8)
                    await ctx.countdown()
                    ctx.hud.ambient = false
                    ctx.micro.juice.reset()
                    let block = await instance.play(familiarization: familiarization, trials: n, seed: blockSeeds[k])
                    ctx.hud.ambient = true
                    guard !Task.isCancelled else { return }
                    ctx.recorder.append(block)
                    ctx.celebrateBlock(scored: !familiarization)
                    ctx.cheer(familiarization ? "Practice done." : "Done!", hold: 1.4)
                    await ctx.clock.wait(1.4)
                }
            }
            ctx.hud.skip = { current.cancel() }
            await withTaskCancellationHandler { await current.value } onCancel: { current.cancel() }
            ctx.hud.skip = nil
            ctx.hud.ambient = true
            instance.teardown()
            ctx.hud.visible = false
            await ctx.clock.wait(1.0)
        }
    }
}
