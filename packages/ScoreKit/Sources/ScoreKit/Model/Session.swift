import Foundation

// Mirrors packages/schema/session.schema.json v0.2.0. Keep in sync.
// Times are seconds since session start. Positions are meters, ARKit world frame, y up.

public struct Participant: Codable, Sendable, Equatable {
    public enum Sex: String, Codable, CaseIterable, Sendable { case female, male, other, unspecified }
    public enum Handedness: String, Codable, CaseIterable, Sendable { case left, right, ambi }

    public var code: String
    public var ageYears: Double
    public var sex: Sex
    public var handedness: Handedness

    public init(code: String, ageYears: Double, sex: Sex = .unspecified, handedness: Handedness = .right) {
        self.code = code; self.ageYears = ageYears; self.sex = sex; self.handedness = handedness
    }

    public static func randomCode() -> String {
        String((0..<5).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
    }
}

public struct Device: Codable, Sendable {
    public var model: String
    public var osVersion: String
    public var appVersion: String
    public init(model: String, osVersion: String, appVersion: String) {
        self.model = model; self.osVersion = osVersion; self.appVersion = appVersion
    }
}

public enum TaskKind: String, Codable, CaseIterable, Sendable {
    case simpleRT = "simple_rt", choiceRT = "choice_rt", corsi, pendulum, pursuit
}

public enum Hand: String, Codable, Sendable { case left, right }

/// Fingertip path for one trial, sampled at the hand tracking rate (about 90 Hz).
public struct Trace: Codable, Sendable {
    public var t: [Double]
    public var p: [V3]
    public init(t: [Double] = [], p: [V3] = []) { self.t = t; self.p = p }
    public mutating func append(_ time: Double, _ point: V3) { t.append(time); p.append(point) }
    public var isEmpty: Bool { t.isEmpty }
}

public struct ReactionTrial: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case go, nogo }
    public enum Outcome: String, Codable, Sendable { case hit, miss, falseAlarm = "false_alarm", correctReject = "correct_reject" }

    public var index: Int
    public var kind: Kind
    public var hand: Hand?
    public var spawnT: Double
    public var moveT: Double?
    public var contactT: Double?
    public var position: V3
    public var eccentricityDeg: Double
    public var outcome: Outcome
    public var trackingGapMs: Double
    /// Distance from fingertip to target center at contact.
    public var endpointErrorM: Double?
    public var trace: Trace?

    public init(index: Int, kind: Kind, hand: Hand?, spawnT: Double, moveT: Double?, contactT: Double?,
                position: V3, eccentricityDeg: Double, outcome: Outcome, trackingGapMs: Double,
                endpointErrorM: Double? = nil, trace: Trace? = nil) {
        self.index = index; self.kind = kind; self.hand = hand; self.spawnT = spawnT; self.moveT = moveT
        self.contactT = contactT; self.position = position; self.eccentricityDeg = eccentricityDeg
        self.outcome = outcome; self.trackingGapMs = trackingGapMs; self.endpointErrorM = endpointErrorM; self.trace = trace
    }

    enum CodingKeys: String, CodingKey {
        case index, kind, hand, spawnT, moveT, contactT, position, eccentricityDeg, outcome, trackingGapMs
        case endpointErrorM, trace
    }

    /// The schema requires `move_t`, `contact_t` and `hand` to be present, null when absent.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(index, forKey: .index)
        try c.encode(kind, forKey: .kind)
        try c.encode(hand, forKey: .hand)
        try c.encode(spawnT, forKey: .spawnT)
        try c.encode(moveT, forKey: .moveT)
        try c.encode(contactT, forKey: .contactT)
        try c.encode(position, forKey: .position)
        try c.encode(eccentricityDeg, forKey: .eccentricityDeg)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(trackingGapMs, forKey: .trackingGapMs)
        try c.encodeIfPresent(endpointErrorM, forKey: .endpointErrorM)
        try c.encodeIfPresent(trace, forKey: .trace)
    }
}

public struct CorsiTrial: Codable, Sendable {
    public var index: Int
    public var span: Int
    public var sequence: [Int]
    public var response: [Int]
    public var correct: Bool
    public var startT: Double?
    public var endT: Double?
    /// Time of each response touch.
    public var tapT: [Double]?

    public init(index: Int, span: Int, sequence: [Int], response: [Int], correct: Bool,
                startT: Double? = nil, endT: Double? = nil, tapT: [Double]? = nil) {
        self.index = index; self.span = span; self.sequence = sequence; self.response = response
        self.correct = correct; self.startT = startT; self.endT = endT; self.tapT = tapT
    }
}

/// Pendulum drop. A bob swings on a cord, the cord releases at a random phase,
/// the bob falls ballistically and the user grasps it.
public struct PendulumTrial: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable { case `catch`, drop, anticipation }

    public var index: Int
    public var lengthM: Double
    public var amplitudeDeg: Double
    public var releaseT: Double
    public var releaseAngleDeg: Double
    public var releasePosition: V3
    public var releaseVelocity: V3
    public var catchT: Double?
    public var catchPosition: V3?
    public var hand: Hand?
    public var outcome: Outcome
    public var trackingGapMs: Double
    /// Thumb-index aperture at release and at catch, meters.
    public var apertureReleaseM: Double?
    public var apertureCatchM: Double?
    public var trace: Trace?

    public init(index: Int, lengthM: Double, amplitudeDeg: Double, releaseT: Double, releaseAngleDeg: Double,
                releasePosition: V3, releaseVelocity: V3, catchT: Double?, catchPosition: V3?, hand: Hand?,
                outcome: Outcome, trackingGapMs: Double, apertureReleaseM: Double? = nil,
                apertureCatchM: Double? = nil, trace: Trace? = nil) {
        self.index = index; self.lengthM = lengthM; self.amplitudeDeg = amplitudeDeg; self.releaseT = releaseT
        self.releaseAngleDeg = releaseAngleDeg; self.releasePosition = releasePosition
        self.releaseVelocity = releaseVelocity; self.catchT = catchT; self.catchPosition = catchPosition
        self.hand = hand; self.outcome = outcome; self.trackingGapMs = trackingGapMs
        self.apertureReleaseM = apertureReleaseM; self.apertureCatchM = apertureCatchM; self.trace = trace
    }

    /// Vertical fall from release to catch. Equivalent to the classic ruler drop distance.
    public var dropM: Double? {
        guard let c = catchPosition, outcome == .catch else { return nil }
        return max(0, releasePosition.y - c.y)
    }
}

/// Smooth pursuit. The target follows a 3D Lissajous path and the fingertip follows it.
public struct PursuitTrial: Codable, Sendable {
    public struct Path: Codable, Sendable {
        public var center: V3
        public var amplitude: V3
        public var frequencyHz: V3
        public var phase: V3
        public init(center: V3, amplitude: V3, frequencyHz: V3, phase: V3) {
            self.center = center; self.amplitude = amplitude; self.frequencyHz = frequencyHz; self.phase = phase
        }
        public func position(at t: Double) -> V3 {
            let w = 2 * Double.pi
            return V3(center.x + amplitude.x * sin(w * frequencyHz.x * t + phase.x),
                      center.y + amplitude.y * sin(w * frequencyHz.y * t + phase.y),
                      center.z + amplitude.z * sin(w * frequencyHz.z * t + phase.z))
        }
    }

    public var index: Int
    public var startT: Double
    public var durationS: Double
    public var path: Path
    /// Sample times, seconds since session start.
    public var t: [Double]
    public var target: [V3]
    /// Fingertip, null while the hand is not tracked.
    public var finger: [V3?]
    public var hand: Hand?
    public var trackingGapMs: Double

    public init(index: Int, startT: Double, durationS: Double, path: Path, t: [Double], target: [V3],
                finger: [V3?], hand: Hand?, trackingGapMs: Double) {
        self.index = index; self.startT = startT; self.durationS = durationS; self.path = path; self.t = t
        self.target = target; self.finger = finger; self.hand = hand; self.trackingGapMs = trackingGapMs
    }
}

public enum Trial: Sendable {
    case reaction(ReactionTrial)
    case corsi(CorsiTrial)
    case pendulum(PendulumTrial)
    case pursuit(PursuitTrial)
}

public struct Block: Codable, Sendable {
    public var task: TaskKind
    public var familiarization: Bool
    public var seed: Int?
    public var trials: [Trial]

    public init(task: TaskKind, familiarization: Bool, seed: Int? = nil, trials: [Trial]) {
        self.task = task; self.familiarization = familiarization; self.seed = seed; self.trials = trials
    }

    enum CodingKeys: String, CodingKey { case task, familiarization, seed, trials }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        task = try c.decode(TaskKind.self, forKey: .task)
        familiarization = try c.decode(Bool.self, forKey: .familiarization)
        seed = try c.decodeIfPresent(Int.self, forKey: .seed)
        switch task {
        case .simpleRT, .choiceRT: trials = try c.decode([ReactionTrial].self, forKey: .trials).map(Trial.reaction)
        case .corsi: trials = try c.decode([CorsiTrial].self, forKey: .trials).map(Trial.corsi)
        case .pendulum: trials = try c.decode([PendulumTrial].self, forKey: .trials).map(Trial.pendulum)
        case .pursuit: trials = try c.decode([PursuitTrial].self, forKey: .trials).map(Trial.pursuit)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(task, forKey: .task)
        try c.encode(familiarization, forKey: .familiarization)
        try c.encodeIfPresent(seed, forKey: .seed)
        var arr = c.nestedUnkeyedContainer(forKey: .trials)
        for trial in trials {
            switch trial {
            case .reaction(let t): try arr.encode(t)
            case .corsi(let t): try arr.encode(t)
            case .pendulum(let t): try arr.encode(t)
            case .pursuit(let t): try arr.encode(t)
            }
        }
    }

    public var reactionTrials: [ReactionTrial] { trials.compactMap { if case .reaction(let t) = $0 { t } else { nil } } }
    public var corsiTrials: [CorsiTrial] { trials.compactMap { if case .corsi(let t) = $0 { t } else { nil } } }
    public var pendulumTrials: [PendulumTrial] { trials.compactMap { if case .pendulum(let t) = $0 { t } else { nil } } }
    public var pursuitTrials: [PursuitTrial] { trials.compactMap { if case .pursuit(let t) = $0 { t } else { nil } } }
}

public struct HealthKitSnapshot: Codable, Sendable {
    public var restingHrBpm: Double?
    public var hrvSdnnMs: Double?
    public var vo2max: Double?
}

public struct Session: Codable, Sendable {
    public static let schemaVersion = "0.2.0"

    public var schemaVersion = Session.schemaVersion
    public var sessionId = UUID().uuidString
    public var startedAt = Date()
    public var participant: Participant
    public var device: Device
    public var blocks: [Block] = []
    public var healthkit: HealthKitSnapshot?

    public init(sessionId: String = UUID().uuidString, startedAt: Date = Date(), participant: Participant,
                device: Device, blocks: [Block] = []) {
        self.sessionId = sessionId; self.startedAt = startedAt; self.participant = participant
        self.device = device; self.blocks = blocks
    }

    /// Scored (non-familiarization) blocks of one task.
    public func scored(_ task: TaskKind) -> [Block] {
        blocks.filter { $0.task == task && !$0.familiarization }
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
