import RealityKit
import ScoreKit
import simd
import UIKit

/// Shared trial loop for Spark and Gate: spawn orbs, watch fingertips every frame, resolve the outcome.
@MainActor
struct ReachTrial {
    let ctx: GameContext
    /// Fingertip counts as touching within the radius plus this tolerance (fingertip pad thickness).
    static let contactSlack: Float = 0.01
    /// Trace starts this long before spawn so onset detection sees the hand at rest.
    static let preRoll = 0.35

    struct Orb {
        let entity: ModelEntity
        let color: UIColor
        let isGo: Bool
    }

    func run(index: Int, kind: ReactionTrial.Kind, go: SIMD3<Float>?, nogo: SIMD3<Float>?,
             window: Double) async -> ReactionTrial {
        var orbs: [Orb] = []
        for (p, isGo) in [(go, true), (nogo, false)] {
            guard let p else { continue }
            let color = isGo ? Theme.go : Theme.nogo
            let e = Micro.orb(color, radius: Theme.Size.target)
            e.position = p
            ctx.layer.addChild(e)
            ctx.micro.appear(e, announce: true)
            orbs.append(Orb(entity: e, color: color, isGo: isGo))
        }
        // Spawn time: the first frame the orbs are in the scene.
        _ = await ctx.clock.next()
        let spawn = ctx.now
        let scored = go ?? nogo!
        let ecc = ctx.eccentricity(of: scored)

        var touched: (Orb, Hand, Double, SIMD3<Float>)?
        while ctx.now - spawn < window, touched == nil, !Task.isCancelled {
            _ = await ctx.clock.next()
            let t = ctx.now - spawn
            for orb in orbs {
                if t > Theme.Motion.appear { ctx.micro.breathe(orb.entity, t: t) }
                let center = orb.entity.position(relativeTo: nil)
                guard let near = ctx.nearestTip(to: center) else { continue }
                ctx.micro.glow(orb.entity, color: orb.color, distance: near.distance)
                if near.distance <= Theme.Size.target + Self.contactSlack {
                    touched = (orb, near.hand, ctx.tracker.state(near.hand)?.t ?? ctx.now, near.tip)
                }
            }
        }

        let outcome: ReactionTrial.Outcome
        var hand: Hand?, contact: Double?, moveT: Double?, trace: Trace?, endpoint: Double?
        if let (orb, h, tContact, tip) = touched {
            outcome = orb.isGo ? .hit : .falseAlarm
            hand = h; contact = tContact
            endpoint = Double(simd_distance(tip, orb.entity.position(relativeTo: nil)))
            let tr = ctx.tracker.buffer.trace(h, spawn - Self.preRoll, tContact)
            trace = tr
            moveT = Kinematics(tr)?.onset(after: spawn, before: tContact)
            ctx.micro.pop(orb.entity, color: orb.isGo ? Theme.paper : Theme.nogo,
                          speedStep: Micro.speedStep(reachTime: tContact - spawn))
            for other in orbs where other.entity !== orb.entity { ctx.micro.dissolve(other.entity) }
            if orb.isGo { ctx.cheer() }
        } else {
            outcome = kind == .go ? .miss : .correctReject
            for orb in orbs {
                if orb.isGo { ctx.micro.sink(orb.entity) } else { ctx.micro.dissolve(orb.entity) }
            }
            if kind == .nogo { ctx.cheer("Good, you left it.") }
        }
        let gap = ctx.tracker.buffer.maxGapMs(hand, spawn, contact ?? spawn + window)
        return ReactionTrial(index: index, kind: kind, hand: hand, spawnT: spawn, moveT: moveT, contactT: contact,
                             position: scored.v3, eccentricityDeg: ecc, outcome: outcome, trackingGapMs: gap,
                             endpointErrorM: endpoint, trace: trace)
    }

    /// Eccentricity bins 0-30, 30-60, 60-90, 90-120 degrees, balanced and shuffled (specs/tasks/simple-reaction.md).
    static func bins(_ n: Int, rng: inout SeededRNG) -> [Double] {
        var bins = (0..<n).map { Double($0 % 4) }
        bins.shuffle(using: &rng)
        return bins.map { $0 * 30 + Double.random(in: 0..<30, using: &rng) }
    }
}
