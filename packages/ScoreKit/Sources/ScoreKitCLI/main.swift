import Foundation
import ScoreKit
import ScoreKitSynth

// scorekit score <session.json>...            print one ScoreReport per session (JSON array)
// scorekit pace <session.json>...             score each session and print pace of aging
// scorekit synth --out DIR [--n 40] [--seed 7]
// scorekit history --out DIR [--age 52] [--pace 0.8] [--sessions 9] [--days 240] [--seed 11]
// scorekit norms                              print the norm table

let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String, _ fallback: String) -> String {
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return fallback }
    return args[i + 1]
}

func load(_ path: String) throws -> Session {
    try Session.decoder.decode(Session.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func write(_ session: Session, to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let name = "\(session.participant.code)-\(session.sessionId.prefix(8)).json"
    try Session.encoder.encode(session).write(to: dir.appending(path: name))
}

func emit<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try ScoreReport.encoder.encode(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

let paths = args.dropFirst().filter { !$0.hasPrefix("--") && $0.hasSuffix(".json") }
let engine = ScoreEngine()

do {
    switch args.first {
    case "score":
        try emit(try paths.map { engine.score(try load($0)) })

    case "pace":
        let reports = try paths.map { engine.score(try load($0)) }.sorted { $0.startedAt < $1.startedAt }
        let points = reports.compactMap { r in
            r.spatialAge.map { PaceOfAging.Point(date: r.startedAt, spatialAge: $0, sd: r.spatialAgeSD ?? 5) }
        }
        struct Out: Encodable { var points: [PaceOfAging.Point]; var pace: PaceOfAging.Pace? }
        try emit(Out(points: points, pace: PaceOfAging.estimate(points)))

    case "synth":
        let out = URL(fileURLWithPath: option("out", "data/synthetic-minigames"))
        let n = Int(option("n", "40"))!
        var synth = Synth(seed: UInt64(option("seed", "7"))!)
        let base = ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z")!
        for i in 0..<n {
            let age = (18 + Double(i) / Double(max(n - 1, 1)) * 62 + synth.rng.uniform(-2, 2)).rounded()
            let s = synth.session(code: String(format: "SYN%03d", i), age: age,
                                  date: base.addingTimeInterval(Double(i) * 600), sessionIndex: i)
            try write(s, to: out)
        }
        print("\(n) sessions -> \(out.path)")

    case "history":
        // One participant across months, with latent biological age moving at `pace` per year.
        let out = URL(fileURLWithPath: option("out", "data/synthetic-history"))
        let age = Double(option("age", "52"))!
        let pace = Double(option("pace", "0.8"))!
        let count = Int(option("sessions", "9"))!
        let days = Double(option("days", "240"))!
        var synth = Synth(seed: UInt64(option("seed", "11"))!)
        let base = ISO8601DateFormatter().date(from: "2026-02-06T09:00:00Z")!
        let bio0 = age - 3
        for i in 0..<count {
            let d = days * Double(i) / Double(max(count - 1, 1))
            let years = d / 365.25
            let s = synth.session(code: "HIST1", age: age + years, bioAge: bio0 + pace * years,
                                  date: base.addingTimeInterval(d * 86_400), sessionIndex: i)
            try write(s, to: out)
        }
        print("\(count) sessions -> \(out.path)")

    case "norms":
        try emit(NormTable.provisional)

    default:
        FileHandle.standardError.write(Data("usage: scorekit score|pace|synth|history|norms\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("scorekit: \(error)\n".utf8))
    exit(1)
}
