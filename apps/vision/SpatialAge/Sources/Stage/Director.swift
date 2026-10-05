import RealityKit
import ScoreKit

/// Runs the queued minigames in order: intro, familiarization, scored block, next game.
@MainActor
final class Director {
    let ctx: GameContext
    /// Run the unscored practice block before each game (Dusk intro toggle "Practice round first").
    let practice: Bool
    /// Caps every block at this many trials (intro demo). Nil runs the game's full counts.
    let trialCap: Int?
    /// Called as each game starts, before its intro. The music bed changes track on it.
    let onGame: @MainActor (Game) -> Void

    init(ctx: GameContext, practice: Bool = true, trialCap: Int? = nil,
         onGame: @escaping @MainActor (Game) -> Void = { _ in }) {
        self.ctx = ctx
        self.practice = practice
        self.trialCap = trialCap
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
            let ctx = ctx, practice = practice, trialCap = trialCap
            let next = index + 1 < games.count ? games[index + 1] : nil
            let current = Task { @MainActor () -> Bool in
                var buddyStays = false
                let blocks: [Bool] = practice ? [true, false] : [false]
                for familiarization in blocks where !Task.isCancelled {
                    let k = familiarization ? 0 : 1
                    let full = familiarization ? game.familiarizationTrials : game.scoredTrials
                    let n = trialCap.map { min($0, full) } ?? full
                    ctx.show(game, familiarization: familiarization, total: n)
                    if let guide = ctx.guide {
                        // Full explanation before the first block; one line between practice and scored.
                        let lines = familiarization || !practice ? game.guideLines : [game.guideAgain]
                        await guide.say(lines, action: familiarization ? "Tap to practice" : "Tap to start", rig: ctx.rig)
                        // Short beat for Buddy to take off so the first trial starts on a clear view.
                        await ctx.clock.wait(0.25)
                    } else {
                        await ctx.clock.wait(familiarization ? 0.8 : 0.5)
                    }
                    await ctx.countdown()
                    ctx.hud.ambient = false
                    ctx.micro.juice.reset()
                    let block = await instance.play(familiarization: familiarization, trials: n, seed: blockSeeds[k])
                    ctx.hud.ambient = true
                    guard !Task.isCancelled else { return false }
                    ctx.recorder.append(block)
                    if !familiarization {
                        // Scored: clear the game, 3D game age reveal, Buddy reads it out and hands over.
                        instance.teardown()
                        buddyStays = await ctx.revealAge(game, next: next)
                        continue
                    }
                    // Scored block next: Buddy starts back from the far ring during the cheer.
                    ctx.guide?.arrive(ctx.rig)
                    ctx.celebrateBlock(scored: false)
                    ctx.cheer("Practice done.", hold: 0.8)
                    await ctx.clock.wait(0.6)
                }
                return buddyStays && !Task.isCancelled
            }
            ctx.hud.skip = { current.cancel() }
            let buddyStays = await withTaskCancellationHandler { await current.value } onCancel: { current.cancel() }
            ctx.hud.skip = nil
            ctx.hud.ambient = true
            // Buddy stays on his twig into the next game's explanation after the reveal hand-over.
            if !buddyStays || Task.isCancelled { ctx.guide?.leave() }
            instance.teardown()
            ctx.hud.visible = false
            await ctx.clock.wait(buddyStays ? 0.15 : 0.4)
        }
    }
}
