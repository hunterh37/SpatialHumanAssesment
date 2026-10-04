import Foundation
import XCTest
@testable import ScoreKit
import ScoreKitSynth

final class MetricMatrixTests: XCTestCase {
    func testOneRowPerSessionWithMetricColumns() throws {
        var synth = Synth(seed: 3)
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        var first = synth.session(code: "AAAAA", age: 30, date: base, sessionIndex: 0)
        first.participant.heightCm = 172
        let repeatPlay = synth.session(code: "AAAAA", age: 30, date: base.addingTimeInterval(3600), sessionIndex: 1)
        var duel = synth.session(code: "BBBBB", age: 60, date: base.addingTimeInterval(60), sessionIndex: 2)
        duel.mode = .duel

        let lines = MetricMatrix.csv([repeatPlay, duel, first]).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4)
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(header, MetricMatrix.columns)
        let rows = lines.dropFirst().map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertTrue(rows.allSatisfy { $0.count == header.count })

        func col(_ row: [String], _ name: String) -> String { row[header.firstIndex(of: name)!] }
        // Sorted by start time: first, duel, repeat.
        XCTAssertEqual(rows.map { col($0, "session_id") }, [first.sessionId, duel.sessionId, repeatPlay.sessionId])
        XCTAssertEqual(rows.map { col($0, "calibration") }, ["1", "0", "0"])
        XCTAssertEqual(col(rows[0], "height_cm"), "172")
        XCTAssertEqual(col(rows[0], "age"), "30")
        XCTAssertFalse(col(rows[0], "reach_rt").isEmpty)
        XCTAssertFalse(col(rows[0], "corsi_span").isEmpty)
    }

    func testV05FieldsRoundTrip() throws {
        var s = Session(participant: Participant(code: "C", ageYears: 50, heightCm: 180, weightKg: 80, posture: .seated),
                        device: Device(model: "RealityDevice14,1", osVersion: "-", appVersion: "1", deviceId: "D1"),
                        mode: .full, priorSessions: 2)
        s.blocks = []
        let json = try XCTUnwrap(String(data: Session.encoder.encode(s), encoding: .utf8))
        for key in ["\"height_cm\":180", "\"posture\":\"seated\"", "\"device_id\":\"D1\"", "\"mode\":\"full\"",
                    "\"prior_sessions\":2", "\"schema_version\":\"0.5.0\""] {
            XCTAssertTrue(json.contains(key), key)
        }
        let back = try Session.decoder.decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(back.participant.posture, .seated)
        XCTAssertEqual(back.priorSessions, 2)
    }
}
