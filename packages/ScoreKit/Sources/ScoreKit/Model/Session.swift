import Foundation

// Mirrors packages/schema/session.schema.json v0.4.0. Keep in sync.
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
    case reachGrab = "reach_grab", wall, colorDots = "color_dots"
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
    /// Spatial Tracking: what announced the object, `audio`, `light` or `both`. Spawn time is the cue onset.
    public var cue: String?

    public init(index: Int, kind: Kind, hand: Hand?, spawnT: Double, moveT: Double?, contactT: Double?,
                position: V3, eccentricityDeg: Double, outcome: Outcome, trackingGapMs: Double,
                endpointErrorM: Double? = nil, trace: Trace? = nil, cue: String? = nil) {
        self.index = index; self.kind = kind; self.hand = hand; self.spawnT = spawnT; self.moveT = moveT
        self.contactT = contactT; self.position = position; self.eccentricityDeg = eccentricityDeg
        self.outcome = outcome; self.trackingGapMs = trackingGapMs; self.endpointErrorM = endpointErrorM; self.trace = trace
        self.cue = cue
    }

    enum CodingKeys: String, CodingKey {
        case index, kind, hand, spawnT, moveT, contactT, position, eccentricityDeg, outcome, trackingGapMs
        case endpointErrorM, trace, cue
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
        try c.encodeIfPresent(cue, forKey: .cue)
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

/// Stick Drop (task `pendulum`). A row of leaves hangs across the view; one lets go and falls under scaled
/// gravity, and the user grasps it before it reaches the ground. Pre-0.4 sessions logged a swinging pendulum
/// bob, which fills `lengthM` and `amplitudeDeg`; Stick Drop logs both as 0.
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
    /// Stick Drop: which leaf in the row fell (0 is leftmost), its angle from head forward at release, and the
    /// gravity scale of the fall (1 is 9.81 m/s^2).
    public var stickIndex: Int?
    public var eccentricityDeg: Double?
    public var gravityScale: Double?

    public init(index: Int, lengthM: Double, amplitudeDeg: Double, releaseT: Double, releaseAngleDeg: Double,
                releasePosition: V3, releaseVelocity: V3, catchT: Double?, catchPosition: V3?, hand: Hand?,
                outcome: Outcome, trackingGapMs: Double, apertureReleaseM: Double? = nil,
                apertureCatchM: Double? = nil, trace: Trace? = nil, stickIndex: Int? = nil,
                eccentricityDeg: Double? = nil, gravityScale: Double? = nil) {
        self.stickIndex = stickIndex; self.eccentricityDeg = eccentricityDeg; self.gravityScale = gravityScale
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

/// Scary Balance (task `reach_grab`). The participant walks to a floor spot, then reaches for an object a set
/// distance from the dominant shoulder. Distances climb past arm's length, so leaning decides the last ones.
/// On some trials a creature passes mid-reach and the participant freezes in place until it is gone.
public struct ReachGrabTrial: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable { case grab, miss }

    /// One freeze while the creature passes. Sampled from the frame the freeze starts to the frame it ends.
    public struct Freeze: Codable, Sendable {
        public var startT: Double
        public var endT: Double
        /// Head path length over the freeze divided by its duration, cm/s.
        public var headSwayCmS: Double
        /// RMS distance of the reaching fingertip from its own mean during the freeze, cm. Nil when untracked.
        public var handDriftCm: Double?
        /// Largest head travel from where it was when the freeze began, cm.
        public var headShiftCm: Double
        /// False when the head moved more than `ReachGrabMetrics.freezeBreakCm` during the freeze.
        public var held: Bool
        public var trackingGapMs: Double

        public init(startT: Double, endT: Double, headSwayCmS: Double, handDriftCm: Double?, headShiftCm: Double,
                    held: Bool, trackingGapMs: Double) {
            self.startT = startT; self.endT = endT; self.headSwayCmS = headSwayCmS; self.handDriftCm = handDriftCm
            self.headShiftCm = headShiftCm; self.held = held; self.trackingGapMs = trackingGapMs
        }
    }

    public var index: Int
    /// Direction from the dominant shoulder, degrees. 0 is straight ahead, positive is toward the dominant side.
    public var azimuthDeg: Double
    public var elevationDeg: Double
    /// Start-pose shoulder to object center, meters.
    public var distanceM: Double
    public var position: V3
    public var spawnT: Double
    public var grabT: Double?
    public var hand: Hand?
    public var outcome: Outcome
    /// Horizontal head travel from the start pose at the grab, meters: how far the participant leaned.
    public var leanM: Double?
    public var trackingGapMs: Double
    public var trace: Trace?
    /// Floor spot the participant walked to before the object appeared, world space.
    public var standAt: V3?
    public var freeze: Freeze?

    public init(index: Int, azimuthDeg: Double, elevationDeg: Double, distanceM: Double, position: V3,
                spawnT: Double, grabT: Double?, hand: Hand?, outcome: Outcome, leanM: Double?,
                trackingGapMs: Double, trace: Trace? = nil, standAt: V3? = nil, freeze: Freeze? = nil) {
        self.standAt = standAt; self.freeze = freeze
        self.index = index; self.azimuthDeg = azimuthDeg; self.elevationDeg = elevationDeg
        self.distanceM = distanceM; self.position = position; self.spawnT = spawnT; self.grabT = grabT
        self.hand = hand; self.outcome = outcome; self.leanM = leanM; self.trackingGapMs = trackingGapMs
        self.trace = trace
    }
}

/// Hole in the wall. A wall with two hand cutouts moves toward the participant, who fits both hands into the
/// cutouts and holds still while it passes. Scored on how still the head and hands stay during the hold.
public struct WallTrial: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable { case cleared, hit }

    public var index: Int
    /// Pose name, for example `arms_out`, `arms_up`, `reach_left`.
    public var pose: String
    public var startT: Double
    /// Hold window: from `holdStartT` until the wall reaches the participant at `passT`.
    public var holdStartT: Double
    public var passT: Double
    /// Cutout centers in world space, meters.
    public var leftTarget: V3
    public var rightTarget: V3
    /// Mean hand-to-cutout distance during the hold, meters. Nil when that hand was not tracked.
    public var leftErrorM: Double?
    public var rightErrorM: Double?
    /// Head path length during the hold divided by the hold duration, cm/s.
    public var headSwayCmS: Double
    /// RMS distance of each tracked hand from its own mean position during the hold, averaged over hands, cm.
    public var handDriftCm: Double?
    public var outcome: Outcome
    public var trackingGapMs: Double

    public init(index: Int, pose: String, startT: Double, holdStartT: Double, passT: Double, leftTarget: V3,
                rightTarget: V3, leftErrorM: Double?, rightErrorM: Double?, headSwayCmS: Double,
                handDriftCm: Double?, outcome: Outcome, trackingGapMs: Double) {
        self.index = index; self.pose = pose; self.startT = startT; self.holdStartT = holdStartT
        self.passT = passT; self.leftTarget = leftTarget; self.rightTarget = rightTarget
        self.leftErrorM = leftErrorM; self.rightErrorM = rightErrorM; self.headSwayCmS = headSwayCmS
        self.handDriftCm = handDriftCm; self.outcome = outcome; self.trackingGapMs = trackingGapMs
    }
}

/// Spatial Memory (task `color_dots`). Balls of several colors and sizes surround the participant. Select:
/// touch every ball that fits a rule ("every blue ball"). Then every ball turns grey and recall asks for either
/// the balls the participant DID touch or the ones they DID NOT. `shown` marks the recall answers, which come
/// from what was touched in select, not from the rule. Pre-0.4 sessions lit dots instead of a select phase and
/// leave the select fields nil.
public struct ColorDotsTrial: Codable, Sendable {
    public var index: Int
    /// Dots that lit during study.
    public var setSize: Int
    /// Azimuth of each dot around the participant, degrees. 0 is ahead, positive is right.
    public var dotAzimuthDeg: [Double]
    public var dotPositions: [V3]
    /// True for the dots that lit.
    public var shown: [Bool]
    /// Dot indexes touched during recall, in order, and when.
    public var touched: [Int]
    public var touchT: [Double]
    public var studyStartT: Double
    /// Recall starts when the dots turn grey.
    public var recallStartT: Double
    public var endT: Double
    public var hits: Int
    public var falseTaps: Int
    public var misses: Int
    /// Largest head yaw away from the start direction during recall, degrees.
    public var maxHeadTurnDeg: Double
    public var trackingGapMs: Double
    /// Select rule, e.g. `color:blue` or `size:large`, and which balls fit it.
    public var rule: String?
    public var ruleMatch: [Bool]?
    /// Ball color names and radii, meters.
    public var colors: [String]?
    public var radii: [Double]?
    /// Balls touched in select, in order, and when. Select starts at `studyStartT`.
    public var selected: [Int]?
    public var selectT: [Double]?
    /// `did` or `didnt`.
    public var recallMode: String?

    public init(index: Int, setSize: Int, dotAzimuthDeg: [Double], dotPositions: [V3], shown: [Bool],
                touched: [Int], touchT: [Double], studyStartT: Double, recallStartT: Double, endT: Double,
                hits: Int, falseTaps: Int, misses: Int, maxHeadTurnDeg: Double, trackingGapMs: Double,
                rule: String? = nil, ruleMatch: [Bool]? = nil, colors: [String]? = nil, radii: [Double]? = nil,
                selected: [Int]? = nil, selectT: [Double]? = nil, recallMode: String? = nil) {
        self.rule = rule; self.ruleMatch = ruleMatch; self.colors = colors; self.radii = radii
        self.selected = selected; self.selectT = selectT; self.recallMode = recallMode
        self.index = index; self.setSize = setSize; self.dotAzimuthDeg = dotAzimuthDeg
        self.dotPositions = dotPositions; self.shown = shown; self.touched = touched; self.touchT = touchT
        self.studyStartT = studyStartT; self.recallStartT = recallStartT; self.endT = endT; self.hits = hits
        self.falseTaps = falseTaps; self.misses = misses; self.maxHeadTurnDeg = maxHeadTurnDeg
        self.trackingGapMs = trackingGapMs
    }
}

public enum Trial: Sendable {
    case reaction(ReactionTrial)
    case corsi(CorsiTrial)
    case pendulum(PendulumTrial)
    case pursuit(PursuitTrial)
    case reachGrab(ReachGrabTrial)
    case wall(WallTrial)
    case colorDots(ColorDotsTrial)
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
        case .reachGrab: trials = try c.decode([ReachGrabTrial].self, forKey: .trials).map(Trial.reachGrab)
        case .wall: trials = try c.decode([WallTrial].self, forKey: .trials).map(Trial.wall)
        case .colorDots: trials = try c.decode([ColorDotsTrial].self, forKey: .trials).map(Trial.colorDots)
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
            case .reachGrab(let t): try arr.encode(t)
            case .wall(let t): try arr.encode(t)
            case .colorDots(let t): try arr.encode(t)
            }
        }
    }

    public var reactionTrials: [ReactionTrial] { trials.compactMap { if case .reaction(let t) = $0 { t } else { nil } } }
    public var corsiTrials: [CorsiTrial] { trials.compactMap { if case .corsi(let t) = $0 { t } else { nil } } }
    public var pendulumTrials: [PendulumTrial] { trials.compactMap { if case .pendulum(let t) = $0 { t } else { nil } } }
    public var pursuitTrials: [PursuitTrial] { trials.compactMap { if case .pursuit(let t) = $0 { t } else { nil } } }
    public var reachGrabTrials: [ReachGrabTrial] { trials.compactMap { if case .reachGrab(let t) = $0 { t } else { nil } } }
    public var wallTrials: [WallTrial] { trials.compactMap { if case .wall(let t) = $0 { t } else { nil } } }
    public var colorDotsTrials: [ColorDotsTrial] { trials.compactMap { if case .colorDots(let t) = $0 { t } else { nil } } }
}

public struct HealthKitSnapshot: Codable, Sendable {
    public var restingHrBpm: Double?
    public var hrvSdnnMs: Double?
    public var vo2max: Double?
}

public struct Session: Codable, Sendable {
    public static let schemaVersion = "0.4.0"

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
