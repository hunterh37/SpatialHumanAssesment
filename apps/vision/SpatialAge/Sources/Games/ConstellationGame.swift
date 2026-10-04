import RealityKit
import ScoreKit
import simd
import UIKit

/// Constellation. Nine stars hang around you. Some light in turn; touch them back in the same order.
/// 3D Corsi block tapping with the standard staircase. Spec: specs/games/constellation.md.
@MainActor
final class ConstellationGame: Minigame {
    static let game = Game.constellation
    static let count = 9
    static let on = 0.8, off = 0.2
    static let maxSpan = 9
    static let capSeconds = 240.0
    /// A star must be left by this distance before it can be touched again.
    static let rearm: Float = 0.08

    let ctx: GameContext
    private var stars: [ModelEntity] = []

    init(_ ctx: GameContext) { self.ctx = ctx }

    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block {
        var rng = SeededRNG(seed: seed)
        if stars.isEmpty { layout(rng: &rng) }
        var out: [Trial] = []
        var span = 2, idx = 0
        let started = ctx.now
        staircase: while span <= Self.maxSpan, idx < trials {
            var fails = 0
            for _ in 0..<2 {
                guard idx < trials, ctx.now - started < Self.capSeconds, !Task.isCancelled else { break staircase }
                var ids = Array(0..<Self.count)
                ids.shuffle(using: &rng)
                let trial = await sequence(index: idx, span: span, ids: Array(ids.prefix(span)))
                out.append(.corsi(trial))
                idx += 1
                ctx.hud.done = idx
                if !trial.correct { fails += 1 }
                await ctx.clock.wait(1.0)
            }
            if fails == 2 { break }
            span += 1
        }
        return Block(task: .corsi, familiarization: familiarization, seed: seed, trials: out)
    }

    func teardown() { stars.forEach { $0.removeFromParent() }; stars = [] }

    /// Stars spread over 140 degrees of azimuth so the far ones need a head turn. At least 18 cm apart.
    private func layout(rng: inout SeededRNG) {
        var points: [SIMD3<Float>] = []
        var attempts = 0
        while points.count < Self.count && attempts < 2000 {
            attempts += 1
            let slot = Double(points.count) / Double(Self.count - 1)
            let az = -70 + 140 * slot + .random(in: -8...8, using: &rng)
            let p = ctx.reachPoint(azimuthDeg: az, elevationDeg: .random(in: -20...25, using: &rng),
                                   reach: .random(in: 0.45...0.62, using: &rng))
            if points.allSatisfy({ simd_distance($0, p) >= 0.18 }) { points.append(p) }
        }
        for p in points {
            let s = Micro.orb(Theme.paper, radius: Theme.Size.star)
            s.model?.materials = [Look.glow(Theme.mute, intensity: 0.15)]
            s.position = p
            ctx.layer.addChild(s)
            ctx.micro.appear(s)
            stars.append(s)
        }
    }

    private func light(_ i: Int, _ color: UIColor, intensity: Float, scale: Float) {
        stars[i].model?.materials = [Look.glow(color, intensity: intensity)]
        stars[i].scale = .init(repeating: scale)
    }

    private func rest(_ i: Int) { light(i, Theme.mute, intensity: 0.15, scale: 1) }

    private func sequence(index: Int, span: Int, ids: [Int]) async -> CorsiTrial {
        let start = ctx.now
        for id in ids {
            light(id, Theme.gold, intensity: 3, scale: 1.15)
            Tone.play(.star(id), on: stars[id], gain: -14)
            await ctx.clock.wait(Self.on)
            rest(id)
            await ctx.clock.wait(Self.off)
        }

        // Response. All stars breathe and the ready cue sounds: your turn.
        ctx.micro.cue(.ready, at: ctx.rig.world([0, ctx.rig.eye, -0.5]), gain: -16)
        var response: [Int] = [], taps: [Double] = []
        var armed = Array(repeating: true, count: stars.count)
        let deadline = ctx.now + 8 + Double(span)
        var t = 0.0
        while response.count < span, ctx.now < deadline, !Task.isCancelled {
            t += await ctx.clock.next()
            for (i, star) in stars.enumerated() {
                ctx.micro.breathe(star, t: t)
                guard let near = ctx.nearestTip(to: star.position) else { continue }
                if near.distance > Self.rearm { armed[i] = true; continue }
                guard armed[i], near.distance <= Theme.Size.star + 0.015 else { continue }
                armed[i] = false
                response.append(i)
                taps.append(ctx.tracker.state(near.hand)?.t ?? ctx.now)
                flash(i)
                if ids[response.count - 1] != i { break }
            }
            if let last = response.last, ids[response.count - 1] != last { break }
        }
        stars.indices.forEach { stars[$0].scale = .one }

        let correct = response == ids
        if correct {
            for id in ids { ctx.micro.ring(at: stars[id].position, color: Theme.gold, radius: Theme.Size.star * 2) }
            if let last = ids.last { ctx.micro.juice.success(at: stars[last].position(relativeTo: nil)) }
            ctx.cheer()
        } else {
            ctx.micro.juice.reset()
            // A wrong star gets the wrong cue from that star; running out of time gets the quiet miss.
            if let last = response.last, ids[response.count - 1] != last {
                Tone.play(.wrong, on: stars[last], gain: -15)
            } else {
                Tone.play(.miss, on: stars[response.last ?? ids[0]], gain: -20)
            }
        }
        return CorsiTrial(index: index, span: span, sequence: ids, response: response, correct: correct,
                          startT: start, endT: ctx.now, tapT: taps)
    }

    /// Touched star flashes white for 150 ms.
    private func flash(_ i: Int) {
        light(i, Theme.paper, intensity: 3.5, scale: 1.2)
        Tone.play(.star(i), on: stars[i], gain: -16)
        ctx.clock.animate(0.15, { _ in }, done: { [weak self] in self?.rest(i) })
    }
}
