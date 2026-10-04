/// Every measurement the score engine can produce. Raw values are stable identifiers in report JSON.
public enum MetricID: String, CaseIterable, Codable, Sendable, Comparable {
    // Pendulum
    case catchLatency = "catch_latency"
    case catchDropCm = "catch_drop_cm"
    case catchRate = "catch_rate"
    // Spark
    case reachRT = "reach_rt"
    case reachMT = "reach_mt"
    case rtTau = "rt_tau"
    case rtCV = "rt_cv"
    case eccSlope = "ecc_slope"
    case peakSpeed = "peak_speed"
    case pathEfficiency = "path_efficiency"
    case smoothness
    // Gate
    case choiceRT = "choice_rt"
    case decisionTime = "decision_time"
    case commissionRate = "commission_rate"
    case omissionRate = "omission_rate"
    case dPrime = "d_prime"
    // Constellation
    case corsiSpan = "corsi_span"
    case corsiTotal = "corsi_total"
    case corsiTapInterval = "corsi_tap_interval"
    // Orbit
    case pursuitRMS = "pursuit_rms_cm"
    case pursuitLag = "pursuit_lag_ms"
    case pursuitOnTarget = "pursuit_on_target"
    case pursuitGain = "pursuit_gain"
    // Reach and grab
    case reachMaxCm = "reach_max_cm"
    case reachLeanCm = "reach_lean_cm"
    case reachGrabRate = "reach_grab_rate"
    // Hole in the wall
    case wallSwayCmS = "wall_sway_cms"
    case wallHandDriftCm = "wall_hand_drift_cm"
    case wallClearRate = "wall_clear_rate"
    // Color dots
    case dotsSpan = "dots_span"
    case dotsAccuracy = "dots_accuracy"
    case dotsFalseRate = "dots_false_rate"
    case dotsDecisionTime = "dots_decision_time"

    public static func < (a: MetricID, b: MetricID) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    public var game: Game {
        switch self {
        case .catchLatency, .catchDropCm, .catchRate: .pendulum
        case .reachRT, .reachMT, .rtTau, .rtCV, .eccSlope, .peakSpeed, .pathEfficiency, .smoothness: .spark
        case .choiceRT, .decisionTime, .commissionRate, .omissionRate, .dPrime: .gate
        case .corsiSpan, .corsiTotal, .corsiTapInterval: .constellation
        case .pursuitRMS, .pursuitLag, .pursuitOnTarget, .pursuitGain: .orbit
        case .reachMaxCm, .reachLeanCm, .reachGrabRate: .reach
        case .wallSwayCmS, .wallHandDriftCm, .wallClearRate: .wall
        case .dotsSpan, .dotsAccuracy, .dotsFalseRate, .dotsDecisionTime: .dots
        }
    }

    public var label: String {
        switch self {
        case .catchLatency: "Catch latency"
        case .catchDropCm: "Drop distance"
        case .catchRate: "Catch rate"
        case .reachRT: "Reaction time"
        case .reachMT: "Movement time"
        case .rtTau: "RT tail (tau)"
        case .rtCV: "RT variability"
        case .eccSlope: "Eccentricity cost"
        case .peakSpeed: "Peak hand speed"
        case .pathEfficiency: "Path efficiency"
        case .smoothness: "Smoothness (LDLJ)"
        case .choiceRT: "Choice RT"
        case .decisionTime: "Decision time"
        case .commissionRate: "Commission rate"
        case .omissionRate: "Omission rate"
        case .dPrime: "Sensitivity d'"
        case .corsiSpan: "Corsi span"
        case .corsiTotal: "Corsi total"
        case .corsiTapInterval: "Recall tap interval"
        case .pursuitRMS: "Tracking error"
        case .pursuitLag: "Tracking lag"
        case .pursuitOnTarget: "Time on target"
        case .pursuitGain: "Velocity gain"
        case .reachMaxCm: "Furthest grab"
        case .reachLeanCm: "Lean distance"
        case .reachGrabRate: "Grab rate"
        case .wallSwayCmS: "Head sway"
        case .wallHandDriftCm: "Hand drift"
        case .wallClearRate: "Walls cleared"
        case .dotsSpan: "Dot span"
        case .dotsAccuracy: "Recall accuracy"
        case .dotsFalseRate: "False taps"
        case .dotsDecisionTime: "Recall start time"
        }
    }

    public var unit: String {
        switch self {
        case .catchLatency, .reachRT, .reachMT, .rtTau, .choiceRT, .decisionTime, .corsiTapInterval,
             .dotsDecisionTime: "s"
        case .catchDropCm, .pursuitRMS, .reachMaxCm, .reachLeanCm, .wallHandDriftCm: "cm"
        case .wallSwayCmS: "cm/s"
        case .pursuitLag: "ms"
        case .peakSpeed: "m/s"
        case .eccSlope: "s/90°"
        case .catchRate, .commissionRate, .omissionRate, .pursuitOnTarget, .pathEfficiency, .reachGrabRate,
             .wallClearRate, .dotsAccuracy, .dotsFalseRate: "ratio"
        case .rtCV, .smoothness, .dPrime, .corsiSpan, .corsiTotal, .pursuitGain, .dotsSpan: ""
        }
    }
}

/// One measured value with the evidence behind it.
public struct MetricValue: Codable, Sendable {
    public var id: MetricID
    public var value: Double
    /// Trials that contributed.
    public var n: Int
    /// Standard error of `value` from within-session trial spread. Nil when not estimable.
    public var sem: Double?

    public init(_ id: MetricID, _ value: Double, n: Int, sem: Double? = nil) {
        self.id = id; self.value = value; self.n = n; self.sem = sem
    }
}

/// Trial accounting shared by all games.
public struct TrialQuality: Codable, Sendable {
    /// Trials with a hand tracking gap longer than this are dropped (specs/features.md).
    public static let maxGapMs = 100.0

    public var total = 0
    public var kept = 0
    public var worstGapMs = 0.0

    public mutating func count(gapMs: Double, limit: Double = TrialQuality.maxGapMs) -> Bool {
        total += 1
        worstGapMs = max(worstGapMs, gapMs)
        guard gapMs <= limit else { return false }
        kept += 1
        return true
    }

    public mutating func merge(_ o: TrialQuality) {
        total += o.total; kept += o.kept; worstGapMs = max(worstGapMs, o.worstGapMs)
    }

    public init() {}

    public var validRate: Double? { total > 0 ? Double(kept) / Double(total) : nil }
}

/// A per-game extractor turns scored blocks into measurements.
public protocol MetricExtractor {
    static var game: Game { get }
    static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality)
}

public extension Array where Element == MetricValue {
    subscript(_ id: MetricID) -> MetricValue? { first { $0.id == id } }
}
