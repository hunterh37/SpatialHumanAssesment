import Foundation
import XCTest
@testable import ScoreKit

final class ColorDotsMetricsTests: XCTestCase {
    /// A finished trial with `setSize + 4` dots. The touches are the lit dots first, then the decoys, 0.4 s apart,
    /// and the first one lands `firstTouch` seconds after recall starts.
    func trial(_ index: Int, setSize: Int, hits: Int, falseTaps: Int, firstTouch: Double = 1.0,
               gapMs: Double = 10) -> ColorDotsTrial {
        let count = setSize + 4
        let recall = 10.0 * Double(index + 1)
        let touched = Array(0..<hits) + Array(setSize..<(setSize + falseTaps))
        return ColorDotsTrial(
            index: index, setSize: setSize,
            dotAzimuthDeg: (0..<count).map { Double($0) * 20 - 100 },
            dotPositions: (0..<count).map { V3(0.1 * Double($0), 1.3, -0.5) },
            shown: (0..<count).map { $0 < setSize },
            touched: touched, touchT: touched.indices.map { recall + firstTouch + 0.4 * Double($0) },
            studyStartT: recall - 6, recallStartT: recall, endT: recall + 6,
            hits: hits, falseTaps: falseTaps, misses: setSize - hits, maxHeadTurnDeg: 40, trackingGapMs: gapMs)
    }

    func block(_ trials: [ColorDotsTrial], familiarization: Bool = false) -> Block {
        Block(task: .colorDots, familiarization: familiarization, seed: 1, trials: trials.map(Trial.colorDots))
    }

    func session(_ blocks: [Block]) -> Session {
        Session(participant: Participant(code: "TEST", ageYears: 40),
                device: Device(model: "test", osVersion: "0", appVersion: "0"), blocks: blocks)
    }

    /// Three kept trials and a perfect fourth that a 150 ms tracking gap drops. Without the gap it would lift the
    /// span to 6 and push the decision time up.
    var scored: Block {
        block([trial(0, setSize: 3, hits: 3, falseTaps: 0, firstTouch: 0.8),
               trial(1, setSize: 4, hits: 4, falseTaps: 0, firstTouch: 1.0),
               trial(2, setSize: 5, hits: 3, falseTaps: 1, firstTouch: 1.2),
               trial(3, setSize: 6, hits: 6, falseTaps: 0, firstTouch: 3.0, gapMs: 150)])
    }

    func testMetricsFromAStaircaseBlock() throws {
        // Familiarization is never scored, even when it is perfect.
        let practice = block([trial(9, setSize: 8, hits: 8, falseTaps: 0, firstTouch: 0.1)], familiarization: true)
        let (metrics, quality) = ColorDotsMetrics.extract(session([practice, scored]))

        XCTAssertEqual(quality.total, 4)
        XCTAssertEqual(quality.kept, 3)
        XCTAssertEqual(quality.worstGapMs, 150, accuracy: 1e-9)

        // Perfect trials are set sizes 3 and 4.
        let span = try XCTUnwrap(metrics[.dotsSpan])
        XCTAssertEqual(span.value, 4)
        XCTAssertEqual(span.n, 3)

        // Per trial 3/3, 4/4, (3 - 1)/5. Mean 0.8, standard error sqrt(0.12 / 3) = 0.2.
        let accuracy = try XCTUnwrap(metrics[.dotsAccuracy])
        XCTAssertEqual(accuracy.value, 0.8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(accuracy.sem), 0.2, accuracy: 1e-9)

        // One false tap in 3 + 4 + 4 = 11 touches.
        let falseRate = try XCTUnwrap(metrics[.dotsFalseRate])
        XCTAssertEqual(falseRate.value, 1.0 / 11.0, accuracy: 1e-9)
        XCTAssertEqual(falseRate.n, 11)
        XCTAssertEqual(try XCTUnwrap(falseRate.sem), GateMetrics.binomialSE(1, 11), accuracy: 1e-12)

        // Median of 0.8, 1.0, 1.2. Fewer than 5 values are never trimmed, so it is the middle one.
        XCTAssertEqual(try XCTUnwrap(metrics[.dotsDecisionTime]).value, 1.0, accuracy: 1e-9)
    }

    func testNothingToMeasure() throws {
        // One trial with no touch: no span, no false rate, no decision time. Accuracy is 0 and has no SE yet.
        let (metrics, quality) = ColorDotsMetrics.extract(session([block([trial(0, setSize: 3, hits: 0, falseTaps: 0)])]))
        XCTAssertEqual(quality.kept, 1)
        XCTAssertNil(metrics[.dotsSpan])
        XCTAssertNil(metrics[.dotsFalseRate])
        XCTAssertNil(metrics[.dotsDecisionTime])
        let accuracy = try XCTUnwrap(metrics[.dotsAccuracy])
        XCTAssertEqual(accuracy.value, 0, accuracy: 1e-9)
        XCTAssertNil(accuracy.sem)

        // No dots block at all.
        let empty = ColorDotsMetrics.extract(session([]))
        XCTAssertTrue(empty.metrics.isEmpty)
        XCTAssertEqual(empty.quality.total, 0)
    }

    func testAccuracyNeverGoesBelowZero() throws {
        // Two false taps and no hit is 0, not -2/3, and every touch was a false one.
        let (metrics, _) = ColorDotsMetrics.extract(session([block([trial(0, setSize: 3, hits: 0, falseTaps: 2)])]))
        XCTAssertEqual(try XCTUnwrap(metrics[.dotsAccuracy]).value, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics[.dotsFalseRate]).value, 1, accuracy: 1e-9)
    }

    func testEngineReportsTheDotsGame() throws {
        let report = ScoreEngine().score(session([scored]))
        let dots = try XCTUnwrap(report.games.first { $0.game == .dots })
        XCTAssertTrue(dots.played)
        XCTAssertEqual(dots.trialsScored, 4)
        XCTAssertEqual(dots.trialsKept, 3)
        XCTAssertEqual(try XCTUnwrap(report.metrics.first { $0.id == .dotsSpan }).value, 4)

        let none = ScoreEngine().score(session([]))
        XCTAssertFalse(try XCTUnwrap(none.games.first { $0.game == .dots }).played)
    }

    func testTrialsSurviveTheJSONRoundTrip() throws {
        let data = try Session.encoder.encode(session([scored]))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"color_dots\""))
        XCTAssertTrue(json.contains("\"max_head_turn_deg\""))
        let back = try Session.decoder.decode(Session.self, from: data)
        XCTAssertEqual(back.scored(.colorDots).flatMap(\.colorDotsTrials).count, 4)
        XCTAssertEqual(try XCTUnwrap(ColorDotsMetrics.extract(back).metrics[.dotsAccuracy]).value, 0.8, accuracy: 1e-9)
    }
}
