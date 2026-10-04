import Foundation
import ScoreKit

/// Synthetic telemetry for building and testing the pipeline without a headset.
///
/// Each participant gets a latent "biological age" = chronological + noise, and every behavior is drawn
/// from physical models (minimum-jerk reaches, ex-Gaussian RTs, ballistic pendulum, lagged pursuit)
/// whose parameters drift with that latent age. Effect sizes are invented.
/// Never use synthetic data to report model accuracy.
public struct Synth {
    public var rng: SplitMix64
    public init(seed: UInt64) { rng = SplitMix64(seed: seed) }

    // MARK: Participant physiology

    public struct Physiology {
        public var bioAge: Double
        var rtMu, rtTau, mt, faRate, missRate, span, catchLat, catchTau, pursuitRMS, pursuitLag, fumble: Double
        var submovementP: Double
        var decision: Double
        var bow: Double
    }

    public mutating func physiology(bioAge a: Double) -> Physiology {
        let late = max(0, a - 50)
        func jitter(_ sd: Double) -> Double { rng.gauss(0, sd) }
        return Physiology(
            bioAge: a,
            rtMu: 0.265 + 0.0012 * (a - 25) + 0.000015 * late * late + jitter(0.02),
            rtTau: max(0.012, 0.035 + 0.0006 * (a - 25) + jitter(0.008)),
            mt: 0.36 + 0.0024 * (a - 25) + jitter(0.03),
            faRate: min(0.4, max(0.01, 0.05 + 0.0012 * (a - 25) + jitter(0.02))),
            missRate: min(0.2, max(0, 0.01 + 0.0003 * (a - 25))),
            span: 6.4 - 0.03 * (a - 25) - 0.0004 * late * late + jitter(0.5),
            catchLat: 0.165 + 0.0008 * (a - 25) + 0.00001 * late * late + jitter(0.012),
            catchTau: max(0.008, 0.02 + 0.0003 * (a - 25)),
            pursuitRMS: max(0.012, 0.026 + 0.0004 * (a - 25) + 0.000005 * late * late + jitter(0.004)),
            pursuitLag: max(0.05, 0.11 + 0.0015 * (a - 25) + jitter(0.015)),
            fumble: min(0.3, max(0.01, 0.03 + 0.0015 * (a - 25))),
            submovementP: min(0.8, max(0.05, 0.1 + 0.009 * (a - 25))),
            decision: 0.12 + 0.001 * (a - 25) + jitter(0.02),
            bow: max(0.005, 0.02 + 0.0004 * (a - 25) + jitter(0.006)))
    }

    // MARK: Session

    public mutating func session(code: String, age: Double, bioAge: Double? = nil, date: Date,
                                 sessionIndex: Int = 0) -> Session {
        let bio = bioAge ?? age + rng.gauss(0, 6)
        let phys = physiology(bioAge: bio)
        var clock = 2.0
        var blocks: [Block] = []
        for game in Game.allCases {
            for fam in [true, false] {
                let n = fam ? game.familiarizationTrials : game.scoredTrials
                let seed = Int(rng.next() % (1 << 31))
                // Familiarization runs a little slower, as practice would.
                var p = phys
                if fam { p.rtMu += 0.04; p.catchLat += 0.02 }
                blocks.append(block(game, p, n: n, familiarization: fam, clock: &clock, seed: seed))
                clock += 4
            }
        }
        var id = rng.next()
        let uuid = withUnsafeBytes(of: &id) { b in
            UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], 0x40, 0x80, b[0], b[1], b[2], b[3],
                        UInt8(sessionIndex & 0xff), 0)).uuidString
        }
        return Session(sessionId: uuid, startedAt: date,
                       participant: Participant(code: code, ageYears: age, sex: .unspecified, handedness: .right),
                       device: Device(model: "synthetic", osVersion: "-", appVersion: "scorekit-synth"),
                       blocks: blocks)
    }

    mutating func block(_ g: Game, _ p: Physiology, n: Int, familiarization: Bool, clock: inout Double, seed: Int) -> Block {
        switch g {
        case .spark: return Block(task: .simpleRT, familiarization: familiarization, seed: seed,
                                  trials: (0..<n).map { .reaction(reaction($0, p, choice: false, clock: &clock)) })
        case .gate: return Block(task: .choiceRT, familiarization: familiarization, seed: seed,
                                 trials: (0..<n).map { .reaction(reaction($0, p, choice: true, clock: &clock)) })
        case .pendulum: return Block(task: .pendulum, familiarization: familiarization, seed: seed,
                                     trials: (0..<n).map { .pendulum(pendulum($0, p, clock: &clock)) })
        case .orbit: return Block(task: .pursuit, familiarization: familiarization, seed: seed,
                                  trials: (0..<n).map { .pursuit(pursuit($0, p, clock: &clock)) })
        case .constellation: return Block(task: .corsi, familiarization: familiarization, seed: seed,
                                          trials: corsi(p, familiarization: familiarization, clock: &clock))
        }
    }

    // MARK: Tasks

    static let head = V3(0, 1.55, 0)
    static let restHand = V3(0.18, 1.05, -0.25)

    mutating func gap() -> Double { rng.uniform() < 0.03 ? rng.uniform(110, 260) : abs(rng.gauss(8, 12)) }

    mutating func exGauss(mu: Double, sigma: Double, tau: Double) -> Double {
        rng.gauss(mu, sigma) + rng.exponential(mean: tau)
    }

    mutating func reaction(_ i: Int, _ p: Physiology, choice: Bool, clock: inout Double) -> ReactionTrial {
        let bin = Double(i % 4)
        let ecc = rng.uniform(bin * 30, bin * 30 + 30)
        let az = (rng.uniform() < 0.5 ? -1.0 : 1.0) * ecc * .pi / 180
        let r = rng.uniform(0.38, 0.6)
        let target = V3(sin(az) * r, rng.uniform(1.0, 1.5), -cos(az) * r)
        let spawn = clock + rng.uniform(0.8, 2.0)
        let kind: ReactionTrial.Kind = choice && rng.uniform() < 0.3 ? .nogo : .go
        let gapMs = gap()

        var outcome: ReactionTrial.Outcome = .hit
        if kind == .nogo { outcome = rng.uniform() < p.faRate ? .falseAlarm : .correctReject }
        else if choice && rng.uniform() < p.missRate { outcome = .miss }
        else if choice && rng.uniform() < p.faRate * 0.3 { outcome = .falseAlarm }

        guard outcome == .hit || outcome == .falseAlarm else {
            clock = spawn + 2.0
            return ReactionTrial(index: i, kind: kind, hand: nil, spawnT: spawn, moveT: nil, contactT: nil,
                                 position: target, eccentricityDeg: ecc, outcome: outcome, trackingGapMs: gapMs)
        }
        let rt = max(0.14, exGauss(mu: p.rtMu + (choice ? p.decision : 0), sigma: 0.025, tau: p.rtTau))
        // Eccentric targets need a head turn first.
        let mt = max(0.15, rng.gauss(p.mt + 0.12 * ecc / 90, 0.04))
        let onset = spawn + rt
        let approach = target - (target - Self.restHand) / max(target.distance(to: Self.restHand), 1e-6) * 0.045
        let trace = reachTrace(from: Self.restHand, to: approach, onset: onset, duration: mt, p: p)
        clock = onset + mt + 1.2
        return ReactionTrial(index: i, kind: kind, hand: .right, spawnT: spawn, moveT: onset + 0.03,
                             contactT: onset + mt, position: target, eccentricityDeg: ecc, outcome: outcome,
                             trackingGapMs: gapMs, endpointErrorM: approach.distance(to: target), trace: trace)
    }

    /// Minimum-jerk reach, optionally with a corrective submovement, plus physiological tremor.
    mutating func reachTrace(from a: V3, to b: V3, onset: Double, duration: Double, p: Physiology) -> Trace {
        var trace = Trace()
        let dt = 1 / 90.0
        let corrective = rng.uniform() < p.submovementP
        let split = corrective ? rng.uniform(0.62, 0.78) : 1
        let overshoot = (b - a) * (corrective ? rng.uniform(-0.12, 0.08) : 0)
        let via = a + (b - a) + overshoot
        // Real reaches curve. Bow the path sideways, peaking mid-reach.
        let dir = (b - a) / max(b.distance(to: a), 1e-6)
        var side = V3(-dir.z, 0, dir.x)
        if side.length < 1e-3 { side = V3(1, 0, 0) }
        let bow = side / side.length * (p.bow * rng.uniform(0.6, 1.4))
        var t = onset - 0.35
        while t <= onset + duration + 0.08 {
            let u = (t - onset) / duration
            var pos: V3
            if u <= 0 { pos = a }
            else if u >= 1 { pos = b }
            else if !corrective { pos = a + (b - a) * Self.minJerk(u) }
            else if u < split { pos = a + (via - a) * Self.minJerk(u / split) }
            else { pos = via + (b - via) * Self.minJerk((u - split) / (1 - split)) }
            if u > 0 && u < 1 { pos = pos + bow * sin(.pi * u) }
            let tremor = V3(rng.gauss(0, 0.0012), rng.gauss(0, 0.0012), rng.gauss(0, 0.0012))
            trace.append(t + rng.uniform(-0.002, 0.002), pos + tremor)
            t += dt
        }
        return trace
    }

    static func minJerk(_ u: Double) -> Double { u * u * u * (10 - 15 * u + 6 * u * u) }

    mutating func pendulum(_ i: Int, _ p: Physiology, clock: inout Double) -> PendulumTrial {
        let g = 9.81
        let length = rng.uniform(0.55, 0.85)
        let amp = rng.uniform(22, 34) * .pi / 180
        let pivot = V3(0, 1.95, -0.48)
        let omega = (g / length).squareRoot()
        let swingT = rng.uniform(1.5, 4.0)
        let theta = amp * cos(omega * swingT)
        let thetaDot = -amp * omega * sin(omega * swingT)
        let pos = pivot + V3(length * sin(theta), -length * cos(theta), 0)
        let vel = V3(length * cos(theta) * thetaDot, length * sin(theta) * thetaDot, 0)
        let release = clock + 1.0 + swingT
        let gapMs = gap()

        let anticipation = rng.uniform() < 0.03
        let latency = anticipation ? rng.uniform(0.02, 0.09)
            : max(0.11, exGauss(mu: p.catchLat, sigma: 0.015, tau: p.catchTau))
        let fall = 0.5 * g * latency * latency
        // Bob passes the lowest grasp height (0.75 m) unless caught first, or slips through the hand.
        let floorFall = pos.y - 0.75
        let caught = anticipation || (fall < floorFall && rng.uniform() > p.fumble)
        clock = release + 2.0
        guard caught else {
            return PendulumTrial(index: i, lengthM: length, amplitudeDeg: amp * 180 / .pi, releaseT: release,
                                 releaseAngleDeg: theta * 180 / .pi, releasePosition: pos, releaseVelocity: vel,
                                 catchT: nil, catchPosition: nil, hand: nil, outcome: .drop, trackingGapMs: gapMs,
                                 apertureReleaseM: rng.uniform(0.06, 0.1))
        }
        let catchPos = pos + vel * latency + V3(0, -fall, 0)
        return PendulumTrial(index: i, lengthM: length, amplitudeDeg: amp * 180 / .pi, releaseT: release,
                             releaseAngleDeg: theta * 180 / .pi, releasePosition: pos, releaseVelocity: vel,
                             catchT: release + latency, catchPosition: catchPos, hand: .right,
                             outcome: anticipation ? .anticipation : .catch, trackingGapMs: gapMs,
                             apertureReleaseM: rng.uniform(0.06, 0.1), apertureCatchM: rng.uniform(0.015, 0.03))
    }

    mutating func pursuit(_ i: Int, _ p: Physiology, clock: inout Double) -> PursuitTrial {
        let path = PursuitTrial.Path(center: V3(0, 1.32, -0.45), amplitude: V3(0.2, 0.12, 0.08),
                                     frequencyHz: V3(0.21, 0.29, 0.13),
                                     phase: V3(rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28)))
        let start = clock + 1
        let duration = 12.0
        var ts: [Double] = [], targets: [V3] = [], fingers: [V3?] = []
        // Error is a smooth random walk (Ornstein-Uhlenbeck) scaled to the participant's tracking error.
        var e = V3.zero
        let theta = 1.5, dt = 1 / 30.0
        let sigma = p.pursuitRMS * (2 * theta).squareRoot() / 3.0.squareRoot()
        var dropout = 0
        var worstGap = 0.0, gapRun = 0.0
        var t = 0.0
        while t <= duration {
            let noise = V3(rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)) * (sigma * dt.squareRoot())
            e = e + (e * (-theta * dt)) + noise
            let target = path.position(at: t)
            ts.append(start + t); targets.append(target)
            if dropout == 0 && rng.uniform() < 0.0015 { dropout = Int(rng.uniform(2, 6)) }
            if dropout > 0 {
                dropout -= 1; fingers.append(nil); gapRun += dt * 1000; worstGap = max(worstGap, gapRun)
            } else {
                gapRun = 0
                fingers.append(path.position(at: max(0, t - p.pursuitLag)) + e)
            }
            t += dt
        }
        clock = start + duration + 2
        return PursuitTrial(index: i, startT: start, durationS: duration, path: path, t: ts, target: targets,
                            finger: fingers, hand: .right, trackingGapMs: worstGap)
    }

    mutating func corsi(_ p: Physiology, familiarization: Bool, clock: inout Double) -> [Trial] {
        var trials: [Trial] = []
        var span = 2, idx = 0
        let cap = familiarization ? 1 : Game.constellation.scoredTrials
        while span <= 9 && idx < cap {
            var fails = 0
            for _ in 0..<2 where idx < cap {
                var cubes = Array(0..<9)
                for k in stride(from: 8, to: 0, by: -1) { cubes.swapAt(k, Int(rng.next() % UInt64(k + 1))) }
                let seq = Array(cubes.prefix(span))
                let ok = rng.uniform() < 1 / (1 + exp(2.2 * (Double(span) - p.span)))
                var resp = seq
                if !ok { resp.swapAt(max(0, span - 2), span - 1) ; if span == 2 { resp[1] = cubes[8] } }
                let start = clock
                let present = Double(span) * 1.0
                var taps: [Double] = []
                var tt = start + present + rng.uniform(0.6, 1.0)
                for _ in resp { taps.append(tt); tt += max(0.25, rng.gauss(0.45 + 0.004 * (p.bioAge - 25), 0.1)) }
                trials.append(.corsi(CorsiTrial(index: idx, span: span, sequence: seq, response: resp, correct: ok,
                                                startT: start, endT: tt, tapT: taps)))
                clock = tt + 1.5
                idx += 1
                if !ok { fails += 1 }
            }
            if fails == 2 { break }
            span += 1
        }
        return trials
    }
}

/// Deterministic RNG so synthetic cohorts are reproducible.
public struct SplitMix64 {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func uniform(_ a: Double, _ b: Double) -> Double { a + (b - a) * uniform() }
    public mutating func gauss(_ mu: Double, _ sd: Double) -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return mu + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
    public mutating func exponential(mean: Double) -> Double { -mean * log(max(uniform(), 1e-12)) }
}
