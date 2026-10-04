import Foundation
import XCTest
@testable import ScoreKit

final class ReachGrabMetricsTests: XCTestCase {
    private func grab(_ i: Int, _ distance: Double, lean: Double?, gapMs: Double = 20) -> ReachGrabTrial {
        ReachGrabTrial(index: i, azimuthDeg: 0, elevationDeg: 0, distanceM: distance,
                       position: V3(0, 1.3, -distance), spawnT: 10 + Double(i) * 8, grabT: 12 + Double(i) * 8,
                       hand: .right, outcome: .grab, leanM: lean, trackingGapMs: gapMs)
    }

    private func miss(_ i: Int, _ distance: Double, gapMs: Double = 20) -> ReachGrabTrial {
        ReachGrabTrial(index: i, azimuthDeg: 0, elevationDeg: 0, distanceM: distance,
                       position: V3(0, 1.3, -distance), spawnT: 10 + Double(i) * 8, grabT: nil,
                       hand: nil, outcome: .miss, leanM: nil, trackingGapMs: gapMs)
    }

    private func block(_ trials: [ReachGrabTrial], familiarization: Bool = false) -> Block {
        Block(task: .reachGrab, familiarization: familiarization, seed: 1, trials: trials.map(Trial.reachGrab))
    }

    private func makeSession(_ blocks: [Block]) -> Session {
        Session(participant: Participant(code: "RG1", ageYears: 40),
                device: Device(model: "test", osVersion: "-", appVersion: "0"), blocks: blocks)
    }

    /// Four kept trials (three grabs, one miss) and one dropped by its tracking gap.
    private func mixedSession() -> Session {
        let scored = block([
            grab(0, 0.50, lean: 0.02),
            grab(1, 0.60, lean: 0.05),
            grab(2, 0.70, lean: 0.12),
            miss(3, 0.80),
            grab(4, 0.90, lean: 0.30, gapMs: 150),
        ])
        // Practice reached further than the scored block did. It must not count.
        let practice = block([grab(0, 0.95, lean: 0.50)], familiarization: true)
        return makeSession([practice, scored])
    }

    func testMaxLeanAndRateFromKeptTrials() throws {
        let (metrics, quality) = ReachGrabMetrics.extract(mixedSession())

        let far = try XCTUnwrap(metrics[.reachMaxCm])
        XCTAssertEqual(far.value, 70, accuracy: 1e-9)
        XCTAssertEqual(far.n, 3)
        XCTAssertNil(far.sem)

        let lean = try XCTUnwrap(metrics[.reachLeanCm])
        XCTAssertEqual(lean.value, 12, accuracy: 1e-9)
        XCTAssertEqual(lean.n, 3)
        XCTAssertNil(lean.sem)

        let rate = try XCTUnwrap(metrics[.reachGrabRate])
        XCTAssertEqual(rate.value, 0.75, accuracy: 1e-9)
        XCTAssertEqual(rate.n, 4)
        XCTAssertEqual(try XCTUnwrap(rate.sem), GateMetrics.binomialSE(3, 4), accuracy: 1e-12)

        XCTAssertEqual(quality.total, 5)
        XCTAssertEqual(quality.kept, 4)
        XCTAssertEqual(quality.worstGapMs, 150, accuracy: 1e-9)
    }

    func testScoreEngineReportsReachGame() throws {
        let report = ScoreEngine().score(mixedSession())
        let game = try XCTUnwrap(report.games.first { $0.game == .reach })
        XCTAssertTrue(game.played)
        XCTAssertEqual(game.trialsScored, 5)
        XCTAssertEqual(game.trialsKept, 4)
        XCTAssertEqual(try XCTUnwrap(report.metrics.first { $0.id == .reachMaxCm }).value, 70, accuracy: 1e-9)
    }

    func testPracticeOnlyIsNotPlayed() throws {
        let s = makeSession([block([grab(0, 0.50, lean: 0.02)], familiarization: true)])
        let (metrics, quality) = ReachGrabMetrics.extract(s)
        XCTAssertTrue(metrics.isEmpty)
        XCTAssertEqual(quality.total, 0)
        let game = try XCTUnwrap(ScoreEngine().score(s).games.first { $0.game == .reach })
        XCTAssertFalse(game.played)
    }

    func testAllMissesKeepOnlyTheRate() throws {
        let s = makeSession([block([miss(0, 0.50), miss(1, 0.50)])])
        let (metrics, _) = ReachGrabMetrics.extract(s)
        XCTAssertNil(metrics[.reachMaxCm])
        XCTAssertNil(metrics[.reachLeanCm])
        let rate = try XCTUnwrap(metrics[.reachGrabRate])
        XCTAssertEqual(rate.value, 0, accuracy: 1e-12)
        XCTAssertEqual(rate.n, 2)
        XCTAssertGreaterThan(try XCTUnwrap(rate.sem), 0)
    }

    func testLeanSkipsGrabsWithoutIt() throws {
        let s = makeSession([block([grab(0, 0.50, lean: nil), grab(1, 0.60, lean: 0.08)])])
        let (metrics, _) = ReachGrabMetrics.extract(s)
        XCTAssertEqual(try XCTUnwrap(metrics[.reachMaxCm]).n, 2)
        let lean = try XCTUnwrap(metrics[.reachLeanCm])
        XCTAssertEqual(lean.value, 8, accuracy: 1e-9)
        XCTAssertEqual(lean.n, 1)
    }
}
