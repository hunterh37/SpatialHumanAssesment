import Foundation

// Mirrors packages/schema/session.schema.json v0.1.0. Keep in sync.

struct Participant: Codable {
    enum Sex: String, Codable, CaseIterable { case female, male, other, unspecified }
    enum Handedness: String, Codable, CaseIterable { case left, right, ambi }

    var code: String
    var ageYears: Int
    var sex: Sex
    var handedness: Handedness

    static func randomCode() -> String {
        String((0..<5).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
    }
}

struct Device: Codable {
    var model: String
    var osVersion: String
    var appVersion: String
}

enum TaskKind: String, Codable { case simpleRT = "simple_rt", choiceRT = "choice_rt", corsi }

struct ReactionTrial: Codable {
    enum Kind: String, Codable { case go, nogo }
    enum Outcome: String, Codable { case hit, miss, falseAlarm = "false_alarm", correctReject = "correct_reject" }
    enum Hand: String, Codable { case left, right }

    var index: Int
    var kind: Kind
    var hand: Hand?
    var spawnT: Double
    var moveT: Double?
    var contactT: Double?
    var position: [Float]
    var eccentricityDeg: Double
    var outcome: Outcome
    var trackingGapMs: Double
}

struct CorsiTrial: Codable {
    var index: Int
    var span: Int
    var sequence: [Int]
    var response: [Int]
    var correct: Bool
    var startT: Double
    var endT: Double
}

enum Trial: Codable {
    case reaction(ReactionTrial)
    case corsi(CorsiTrial)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .reaction(let t): try t.encode(to: encoder)
        case .corsi(let t): try t.encode(to: encoder)
        }
    }

    init(from decoder: Decoder) throws {
        if let t = try? CorsiTrial(from: decoder) { self = .corsi(t) }
        else { self = .reaction(try ReactionTrial(from: decoder)) }
    }
}

struct Block: Codable {
    var task: TaskKind
    var familiarization: Bool
    var seed: Int?
    var trials: [Trial]
}

struct Session: Codable {
    var schemaVersion = "0.1.0"
    var sessionId = UUID().uuidString
    var startedAt = Date()
    var participant: Participant
    var device: Device
    var blocks: [Block] = []

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
