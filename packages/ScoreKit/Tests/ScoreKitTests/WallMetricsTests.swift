import Foundation
import XCTest
@testable import ScoreKit

final class WallMetricsTests: XCTestCase {
    /// One logged wall. Everything the metrics do not read is fixed.
    private func wall(_ i: Int, sway: Double, drift: Double?, outcome: WallTrial.Outcome,
                      gapMs: Double = 10) -> WallTrial {
        let start = 10 + Double(i) * 8
        return WallTrial(index: i, pose: "arms_out", startT: start, holdStartT: start + 3.5, passT: start + 5,
                         leftTarget: V3(-0.55, 1.25, -0.3), rightTarget: V3(0.55, 1.25, -0.3),
                         leftErrorM: 0.05, rightErrorM: 0.06, headSwayCmS: sway, handDriftCm: drift,
                         outcome: outcome, trackingGapMs: gapMs)
    }

    private func block(_ trials: [WallTrial], familiarization: Bool = false) -> Block {
        Block(task: .wall, familiarization: familiarization, seed: 1, trials: trials.map(Trial.wall))
    }

    private func makeSession(_ blocks: [Block]) -> Session {
        Session(participant: Participant(code: "WALL1", ageYears: 40),
                device: Device(model: "test", osVersion: "-", appVersion: "0"), blocks: blocks)
    }

    /// Four kept walls (three cleared, one hit) and a fifth dropped by its tracking gap. The dropped wall is
    /// extreme on every metric, so letting it through would move sway, drift and the clear rate.
    private func mixedSession() -> Session {
        let scored = block([
            wall(0, sway: 1.0, drift: 0.5, outcome: .cleared),
            wall(1, sway: 2.0, drift: 1.0, outcome: .cleared),
            wall(2, sway: 3.0, drift: 1.5, outcome: .hit),
            wall(3, sway: 2.0, drift: nil, outcome: .cleared),
            wall(4, sway: 40, drift: 9.0, outcome: .hit, gapMs: 150),
        ])
        // Practice swayed far more than the scored block did. It must not count.
        let practice = block([wall(0, sway: 90, drift: 90, outcome: .hit)], familiarization: true)
        return makeSession([practice, scored])
    }

    func testMediansAndClearRateFromKeptTrials() throws {
        let (metrics, quality) = WallMetrics.extract(mixedSession())

        // Four kept values never reach the outlier trim (it needs five), so this is the plain median of
        // [1, 2, 2, 3]: the mean of the two middle values.
        let sway = try XCTUnwrap(metrics[.wallSwayCmS])
        XCTAssertEqual(sway.value, 2.0, accuracy: 1e-9)
        XCTAssertEqual(sway.n, 4)
        XCTAssertNotNil(sway.sem)

        // The nil drift is skipped, leaving [0.5, 1.0, 1.5].
        let drift = try XCTUnwrap(metrics[.wallHandDriftCm])
        XCTAssertEqual(drift.value, 1.0, accuracy: 1e-9)
        XCTAssertEqual(drift.n, 3)

        let rate = try XCTUnwrap(metrics[.wallClearRate])
        XCTAssertEqual(rate.value, 0.75, accuracy: 1e-9)
        XCTAssertEqual(rate.n, 4)
        // Agresti-Coull: p = (k + 1) / (n + 2) and se = sqrt(p (1 - p) / (n + 2)), here k = 3 and n = 4.
        let p = 4.0 / 6.0
        XCTAssertEqual(try XCTUnwrap(rate.sem), (p * (1 - p) / 6).squareRoot(), accuracy: 1e-9)

        XCTAssertEqual(quality.total, 5)
        XCTAssertEqual(quality.kept, 4)
        XCTAssertEqual(quality.worstGapMs, 150, accuracy: 1e-9)
    }

    func testScoreEngineReportsWallGame() throws {
        let report = ScoreEngine().score(mixedSession())
        let game = try XCTUnwrap(report.games.first { $0.game == .wall })
        XCTAssertTrue(game.played)
        XCTAssertEqual(game.trialsScored, 5)
        XCTAssertEqual(game.trialsKept, 4)
        XCTAssertEqual(try XCTUnwrap(report.metrics.first { $0.id == .wallSwayCmS }).value, 2.0, accuracy: 1e-9)
    }

    func testPracticeOnlyIsNotPlayed() throws {
        let s = makeSession([block([wall(0, sway: 1.0, drift: 0.5, outcome: .cleared)], familiarization: true)])
        let (metrics, quality) = WallMetrics.extract(s)
        XCTAssertTrue(metrics.isEmpty)
        XCTAssertEqual(quality.total, 0)
        let game = try XCTUnwrap(ScoreEngine().score(s).games.first { $0.game == .wall })
        XCTAssertFalse(game.played)
    }

    func testMetricWithoutDataIsOmitted() throws {
        let s = makeSession([block([wall(0, sway: 1.5, drift: nil, outcome: .cleared),
                                    wall(1, sway: 2.5, drift: nil, outcome: .hit)])])
        let (metrics, _) = WallMetrics.extract(s)
        XCTAssertNil(metrics[.wallHandDriftCm])
        XCTAssertEqual(try XCTUnwrap(metrics[.wallSwayCmS]).value, 2.0, accuracy: 1e-9)
        let rate = try XCTUnwrap(metrics[.wallClearRate])
        XCTAssertEqual(rate.value, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rate.n, 2)
    }

    func testAllWallsHitKeepsTheRateAtZero() throws {
        let s = makeSession([block([wall(0, sway: 2.0, drift: 1.0, outcome: .hit),
                                    wall(1, sway: 2.2, drift: 1.1, outcome: .hit)])])
        let (metrics, _) = WallMetrics.extract(s)
        let rate = try XCTUnwrap(metrics[.wallClearRate])
        XCTAssertEqual(rate.value, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(try XCTUnwrap(rate.sem), 0)
        // A hit does not remove the wall from the sway median.
        XCTAssertEqual(try XCTUnwrap(metrics[.wallSwayCmS]).n, 2)
    }
}
