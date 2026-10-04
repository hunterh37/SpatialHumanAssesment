import Foundation
import XCTest
@testable import ScoreKit
@testable import ScoreKitSynth

final class SignalTests: XCTestCase {
    func minJerkTrace(onset: Double, duration: Double, corrective: Bool = false) -> Trace {
        var tr = Trace()
        let a = V3(0, 1, 0), b = V3(0.4, 1.1, -0.2)
        var t = 0.0
        while t < onset + duration + 0.2 {
            let u = min(max((t - onset) / duration, 0), 1)
            var s = Synth.minJerk(u)
            if corrective && u > 0.6 { s = 1.1 - 0.1 * Synth.minJerk((u - 0.6) / 0.4) }
            else if corrective { s = 1.1 * Synth.minJerk(u / 0.6) }
            tr.append(t, a + (b - a) * s)
            t += 1 / 90.0
        }
        return tr
    }

    func testOnsetWithin20ms() throws {
        let kin = try XCTUnwrap(Kinematics(minJerkTrace(onset: 0.5, duration: 0.45)))
        let onset = try XCTUnwrap(kin.onset(after: 0.1))
        XCTAssertEqual(onset, 0.5, accuracy: 0.03)
    }

    func testNoOnsetWhenStill() throws {
        var tr = Trace()
        for i in 0..<90 { tr.append(Double(i) / 90, V3(0, 1, 0)) }
        XCTAssertNil(try XCTUnwrap(Kinematics(tr)).onset(after: 0))
    }

    func testCorrectiveReachIsLessSmooth() throws {
        let clean = try XCTUnwrap(Kinematics(minJerkTrace(onset: 0.3, duration: 0.5)))
        let jerky = try XCTUnwrap(Kinematics(minJerkTrace(onset: 0.3, duration: 0.5, corrective: true)))
        let a = try XCTUnwrap(clean.reach(from: 0.3, to: 0.8))
        let b = try XCTUnwrap(jerky.reach(from: 0.3, to: 0.8))
        XCTAssertGreaterThan(a.ldlj, b.ldlj)
        XCTAssertEqual(a.pathEfficiency, 1, accuracy: 0.01)
        XCTAssertEqual(a.peakSpeed, 1.875 * 0.458 / 0.5, accuracy: 0.1)
    }

    func testExGaussianRecoversTau() throws {
        var rng = SplitMix64(seed: 3)
        let xs = (0..<4000).map { _ in rng.gauss(0.3, 0.03) + rng.exponential(mean: 0.06) }
        let ex = try XCTUnwrap(Stats.exGaussian(xs))
        XCTAssertEqual(ex.tau, 0.06, accuracy: 0.01)
        XCTAssertEqual(ex.mu, 0.3, accuracy: 0.01)
    }

    func testDPrimeAndInverseNormal() throws {
        XCTAssertEqual(Stats.phiInverse(0.975), 1.95996, accuracy: 1e-4)
        XCTAssertEqual(Stats.phi(Stats.phiInverse(0.2)), 0.2, accuracy: 1e-6)
        let d = try XCTUnwrap(Stats.dPrime(hits: 20, goTrials: 21, falseAlarms: 1, nogoTrials: 9))
        XCTAssertGreaterThan(d, 2.5)
    }

    func testTheilSenIgnoresOneOutlier() throws {
        XCTAssertEqual(try XCTUnwrap(Stats.theilSen([0, 1, 2, 3, 4], [0, 1, 2, 30, 4])), 1, accuracy: 1e-9)
    }
}

final class ScoreTests: XCTestCase {
    func testNormInversionRoundTrip() {
        for norm in NormTable.provisional.norms where norm.domain != nil {
            for age in [22.0, 40, 63, 81] {
                XCTAssertEqual(norm.age(for: norm.expected(at: age)), age, accuracy: 0.01, "\(norm.id)")
            }
        }
    }

    func testRulerDrop() {
        XCTAssertEqual(PendulumMetrics.rulerDropCm(latency: 0.2), 19.62, accuracy: 0.01)
    }

    func testOlderLatentAgeScoresOlder() throws {
        var synth = Synth(seed: 1)
        let engine = ScoreEngine()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let young = engine.score(synth.session(code: "Y", age: 25, bioAge: 25, date: date))
        let old = engine.score(synth.session(code: "O", age: 75, bioAge: 75, date: date))
        XCTAssertGreaterThan(try XCTUnwrap(old.evidenceAge), try XCTUnwrap(young.evidenceAge) + 20)
        XCTAssertEqual(young.games.filter(\.played).count, 5)
        XCTAssertTrue(young.quality.usable)
        for d in Domain.allCases {
            let y = try XCTUnwrap(young.domains.first { $0.domain == d }).score
            let o = try XCTUnwrap(old.domains.first { $0.domain == d }).score
            XCTAssertGreaterThan(y, o, "\(d)")
        }
    }

    func testPriorShrinksTowardChronological() throws {
        var synth = Synth(seed: 2)
        let report = ScoreEngine().score(synth.session(code: "S", age: 30, bioAge: 60, date: Date()))
        let evidence = try XCTUnwrap(report.evidenceAge), age = try XCTUnwrap(report.spatialAge)
        XCTAssertLessThan(age, evidence)
        XCTAssertGreaterThan(age, 30)
        XCTAssertLessThan(try XCTUnwrap(report.spatialAgeLow), age)
    }

    func testFamiliarizationIgnored() throws {
        var synth = Synth(seed: 4)
        var s = synth.session(code: "F", age: 40, date: Date())
        let before = ScoreEngine().measure(s).metrics
        for i in s.blocks.indices where s.blocks[i].familiarization { s.blocks[i].trials = [] }
        let after = ScoreEngine().measure(s).metrics
        XCTAssertEqual(before.map(\.value), after.map(\.value))
    }

    func testSessionRoundTripsThroughJSON() throws {
        var synth = Synth(seed: 5)
        let s = synth.session(code: "J", age: 50, date: Date(timeIntervalSince1970: 1_790_000_000))
        let data = try Session.encoder.encode(s)
        let back = try Session.decoder.decode(Session.self, from: data)
        XCTAssertEqual(back.blocks.count, s.blocks.count)
        let a = ScoreEngine().score(s), b = ScoreEngine().score(back)
        XCTAssertEqual(try XCTUnwrap(a.spatialAge), try XCTUnwrap(b.spatialAge), accuracy: 0.05)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"release_angle_deg\""))
        XCTAssertTrue(json.contains("\"schema_version\":\"0.3.0\""))
    }

    func testDecodesV01Example() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../schema/examples/session.example.json")
        let s = try Session.decoder.decode(Session.self, from: Data(contentsOf: url))
        XCTAssertEqual(ScoreEngine().measure(s).metrics[.corsiSpan]?.value, 3)
    }

    func testCorsiReplay() {
        let trials = [CorsiTrial(index: 0, span: 2, sequence: [1, 2], response: [1, 2], correct: true),
                      CorsiTrial(index: 1, span: 3, sequence: [1, 2, 3], response: [1, 3, 2], correct: false)]
        XCTAssertEqual(ConstellationMetrics.replaySpan(trials), 2)
    }

    func testPaceDetectsSlowAging() throws {
        var synth = Synth(seed: 11)
        let engine = ScoreEngine()
        let start = Date(timeIntervalSince1970: 1_770_000_000)
        var points: [PaceOfAging.Point] = []
        for i in 0..<12 {
            let years = Double(i) * 0.25
            let r = engine.score(synth.session(code: "P", age: 50 + years, bioAge: 50 - 6 * years,
                                               date: start.addingTimeInterval(years * 365.25 * 86_400)))
            points.append(.init(date: r.startedAt, spatialAge: r.spatialAge!, sd: r.spatialAgeSD!))
        }
        let pace = try XCTUnwrap(PaceOfAging.estimate(points))
        XCTAssertLessThan(pace.pace, 1)
        XCTAssertNil(PaceOfAging.estimate(Array(points.prefix(2))))
    }
}
