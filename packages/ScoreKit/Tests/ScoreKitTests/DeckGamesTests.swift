import Foundation
import XCTest
@testable import ScoreKit

/// Metrics added for the Games Ideas deck (schema 0.4.0): Stick Drop field of view, Scary Balance freezes,
/// Hole in the Wall hardest pose, Spatial Memory select time and span.
final class DeckGamesTests: XCTestCase {
    private func session(_ blocks: [Block]) -> Session {
        Session(participant: Participant(code: "DECK", ageYears: 40),
                device: Device(model: "test", osVersion: "-", appVersion: "0"), blocks: blocks)
    }

    // MARK: Stick Drop

    private func leaf(_ i: Int, ecc: Double, latency: Double, scale: Double) -> PendulumTrial {
        let release = 10 + Double(i) * 4
        return PendulumTrial(index: i, lengthM: 0, amplitudeDeg: 0, releaseT: release, releaseAngleDeg: ecc,
                             releasePosition: V3(0, 1.6, -0.5), releaseVelocity: .zero, catchT: release + latency,
                             catchPosition: V3(0, 1.6 - 0.5 * 9.81 * scale * latency * latency, -0.5), hand: .right,
                             outcome: .catch, trackingGapMs: 10, stickIndex: i % 7, eccentricityDeg: ecc,
                             gravityScale: scale)
    }

    func testStickDropSlopeAndRulerEquivalentDrop() throws {
        // Latency = 0.2 s + 0.1 s per 90 degrees, so the slope is 0.1 s/90°. Gravity scale varies and must not
        // change the drop distance, which is the 1 g ruler equivalent of the latency.
        let eccs = [0.0, 20, 40, 60, 0, 20, 40, 60]
        let trials = eccs.enumerated().map { i, e in leaf(i, ecc: e, latency: 0.2 + 0.1 * e / 90, scale: 0.25 + 0.1 * Double(i)) }
        let s = session([Block(task: .pendulum, familiarization: false, seed: 1, trials: trials.map(Trial.pendulum))])
        let m = PendulumMetrics.extract(s).metrics
        XCTAssertEqual(try XCTUnwrap(m[.catchEccSlope]).value, 0.1, accuracy: 1e-9)
        let latency = try XCTUnwrap(m[.catchLatency]).value
        XCTAssertEqual(try XCTUnwrap(m[.catchDropCm]).value, PendulumMetrics.rulerDropCm(latency: latency), accuracy: 0.5)
    }

    func testStickDropLatencyUsesFastEndOfRampAndRanksDrops() throws {
        // Slow leaves are caught late (tracked), fast ones at 0.25 s. Only scale >= 0.75 counts.
        var trials = (0..<6).map { leaf($0, ecc: 0, latency: 0.6, scale: 0.25) }
        trials += (6..<10).map { leaf($0, ecc: 0, latency: 0.25, scale: 1.0) }
        let s = session([Block(task: .pendulum, familiarization: false, seed: 1, trials: trials.map(Trial.pendulum))])
        XCTAssertEqual(try XCTUnwrap(PendulumMetrics.extract(s).metrics[.catchLatency]).value, 0.25, accuracy: 1e-9)

        // Two fast drops rank slowest: median of [0.2, 0.3, 0.4, inf, inf] is 0.4.
        XCTAssertEqual(try XCTUnwrap(PendulumMetrics.catchLatency([0.2, 0.3, 0.4], drops: 2)).value, 0.4, accuracy: 1e-9)
        XCTAssertNil(PendulumMetrics.catchLatency([0.2, 0.3], drops: 2))
    }

    // MARK: Scary Balance

    private func reach(_ i: Int, freeze: ReachGrabTrial.Freeze?) -> ReachGrabTrial {
        ReachGrabTrial(index: i, azimuthDeg: 0, elevationDeg: 0, distanceM: 0.6, position: V3(0, 1.3, -0.6),
                       spawnT: 10 + Double(i) * 8, grabT: 12 + Double(i) * 8, hand: .right, outcome: .grab,
                       leanM: 0.05, trackingGapMs: 10, standAt: V3(0, 0, 0), freeze: freeze)
    }

    private func freeze(sway: Double, drift: Double?, held: Bool, gapMs: Double = 10) -> ReachGrabTrial.Freeze {
        .init(startT: 0, endT: 3, headSwayCmS: sway, handDriftCm: drift, headShiftCm: held ? 2 : 12, held: held,
              trackingGapMs: gapMs)
    }

    func testFreezeMetricsSkipGappyFreezes() throws {
        let trials = [
            reach(0, freeze: freeze(sway: 1, drift: 0.5, held: true)),
            reach(1, freeze: nil),
            reach(2, freeze: freeze(sway: 2, drift: 1.0, held: true)),
            reach(3, freeze: freeze(sway: 3, drift: 1.5, held: false)),
            reach(4, freeze: freeze(sway: 50, drift: 20, held: false, gapMs: 200)),
        ]
        let s = session([Block(task: .reachGrab, familiarization: false, seed: 1, trials: trials.map(Trial.reachGrab))])
        let m = ReachGrabMetrics.extract(s).metrics
        XCTAssertEqual(try XCTUnwrap(m[.freezeSwayCmS]).value, 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m[.freezeHandDriftCm]).value, 1.0, accuracy: 1e-9)
        let held = try XCTUnwrap(m[.freezeHeldRate])
        XCTAssertEqual(held.value, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(held.n, 3)
    }

    func testFreezeRoundTripsThroughJSON() throws {
        let s = session([Block(task: .reachGrab, familiarization: false, seed: 1,
                               trials: [.reachGrab(reach(0, freeze: freeze(sway: 1.2, drift: nil, held: true)))])])
        let back = try Session.decoder.decode(Session.self, from: Session.encoder.encode(s))
        let f = try XCTUnwrap(back.blocks[0].reachGrabTrials[0].freeze)
        XCTAssertEqual(f.headSwayCmS, 1.2)
        XCTAssertNil(f.handDriftCm)
        XCTAssertTrue(f.held)
    }

    // MARK: Hole in the Wall

    func testWorstPoseIsTheHighestMeanError() throws {
        func wall(_ i: Int, pose: String, err: Double) -> WallTrial {
            WallTrial(index: i, pose: pose, startT: Double(i) * 8, holdStartT: Double(i) * 8 + 3.5, passT: Double(i) * 8 + 5,
                      leftTarget: V3(-0.5, 1.3, -0.3), rightTarget: V3(0.5, 1.3, -0.3), leftErrorM: err, rightErrorM: err,
                      headSwayCmS: 1, handDriftCm: 0.5, outcome: .cleared, trackingGapMs: 10)
        }
        let trials = [wall(0, pose: "arms_out", err: 0.04), wall(1, pose: "arms_up", err: 0.10),
                      wall(2, pose: "arms_up", err: 0.14), wall(3, pose: "arms_out", err: 0.06)]
        let s = session([Block(task: .wall, familiarization: false, seed: 1, trials: trials.map(Trial.wall))])
        let worst = try XCTUnwrap(WallMetrics.extract(s).metrics[.wallWorstPoseCm])
        XCTAssertEqual(worst.value, 12, accuracy: 1e-9)
        XCTAssertEqual(worst.n, 2)
    }

    // MARK: Spatial Memory

    func testSelectTimeAndSpanUseRuleTargets() throws {
        // Three rule targets of eight balls. Select touches at +0.8, +1.6, +2.4 s. Recall DID NOT: five answers,
        // all found. Span is the rule's three, not the five answers.
        let match = [true, true, true, false, false, false, false, false]
        let trial = ColorDotsTrial(index: 0, setSize: 5, dotAzimuthDeg: Array(repeating: 0, count: 8),
                                   dotPositions: Array(repeating: V3(0, 1.3, -0.5), count: 8),
                                   shown: match.map { !$0 }, touched: [3, 4, 5, 6, 7], touchT: [21, 22, 23, 24, 25],
                                   studyStartT: 10, recallStartT: 20, endT: 26, hits: 5, falseTaps: 0, misses: 0,
                                   maxHeadTurnDeg: 90, trackingGapMs: 10, rule: "color:blue", ruleMatch: match,
                                   colors: Array(repeating: "blue", count: 8), radii: Array(repeating: 0.05, count: 8),
                                   selected: [0, 1, 2], selectT: [10.8, 11.6, 12.4], recallMode: "didnt")
        let s = session([Block(task: .colorDots, familiarization: false, seed: 1, trials: [.colorDots(trial)])])
        let m = ColorDotsMetrics.extract(s).metrics
        XCTAssertEqual(try XCTUnwrap(m[.dotsSelectTime]).value, 0.8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m[.dotsSpan]).value, 3)
        XCTAssertEqual(try XCTUnwrap(m[.dotsAccuracy]).value, 1)
    }

    func testEveryMetricHasANorm() {
        for id in MetricID.allCases { XCTAssertNotNil(NormTable.provisional[id], id.rawValue) }
    }
}
