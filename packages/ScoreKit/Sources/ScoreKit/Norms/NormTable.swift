import Foundation

/// The five scored domains. Each metric that enters the age model belongs to one.
public enum Domain: String, CaseIterable, Codable, Sendable {
    case speed, decision, control, memory, consistency

    public var title: String {
        switch self {
        case .speed: "Speed"
        case .decision: "Decision"
        case .control: "Control"
        case .memory: "Memory"
        case .consistency: "Consistency"
        }
    }
}

/// Population reference for one metric as a function of age.
///
/// Expected value at age `a`: `mean25 + slope * (a - 25) + accel * max(0, a - 50)^2`.
/// The quadratic term models the steeper decline after 50 reported for processing speed and span.
public struct Norm: Codable, Sendable {
    public var id: MetricID
    public var domain: Domain?
    public var mean25: Double
    /// Between-person SD at age 25.
    public var sd25: Double
    /// Change per year of age, in metric units.
    public var slope: Double
    public var accel: Double
    /// Residual error of this metric as an age predictor, in years. Larger means weaker evidence.
    public var tauYears: Double
    public var source: String

    public init(_ id: MetricID, _ domain: Domain?, mean25: Double, sd25: Double, slope: Double,
                accel: Double = 0, tauYears: Double, source: String) {
        self.id = id; self.domain = domain; self.mean25 = mean25; self.sd25 = sd25; self.slope = slope
        self.accel = accel; self.tauYears = tauYears; self.source = source
    }

    public func expected(at age: Double) -> Double {
        let late = max(0, age - 50)
        return mean25 + slope * (age - 25) + accel * late * late
    }

    /// d expected / d age.
    public func rate(at age: Double) -> Double { slope + 2 * accel * max(0, age - 50) }

    /// +1 when larger values look older.
    public var direction: Double { slope >= 0 ? 1 : -1 }

    /// Age whose expected value equals `value`, by bisection on the monotone curve. Clamped to the range.
    public func age(for value: Double, range: ClosedRange<Double> = 18...95) -> Double {
        let f = { (a: Double) in (expected(at: a) - value) * direction }
        var lo = range.lowerBound, hi = range.upperBound
        if f(lo) >= 0 { return lo }
        if f(hi) <= 0 { return hi }
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if f(mid) < 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// z against the age-25 reference, signed so positive means older-looking.
    public func agingZ(_ value: Double) -> Double { (value - mean25) / sd25 * direction }
}

/// A versioned set of norms. Swap the table, keep the engine.
public struct NormTable: Codable, Sendable {
    public var version: String
    public var norms: [Norm]

    public subscript(_ id: MetricID) -> Norm? { norms.first { $0.id == id } }

    /// v0 priors. Every value is provisional until refit on collected sessions (specs/age-model.md v1).
    /// Sources name the study the shape comes from; the numbers are set for a fingertip reach task in
    /// a headset, which none of those studies used, so they need calibration.
    public static let provisional = NormTable(version: "prior-0.2", norms: [
        Norm(.catchLatency, .speed, mean25: 0.19, sd25: 0.025, slope: 0.0009, accel: 0.000012, tauYears: 14,
             source: "Ruler drop RT shape: Eckner et al. 2010; age slope after Der and Deary 2006"),
        Norm(.catchDropCm, nil, mean25: 17.7, sd25: 4.5, slope: 0.17, tauYears: 99,
             source: "Display only. Derived from catch latency, d = g t^2 / 2"),
        Norm(.catchRate, .control, mean25: 0.95, sd25: 0.05, slope: -0.0015, accel: -0.00003, tauYears: 26,
             source: "Prior, no published reference for this task"),
        Norm(.reachRT, .speed, mean25: 0.30, sd25: 0.04, slope: 0.0015, accel: 0.00002, tauYears: 13,
             source: "Simple RT age curve: Der and Deary 2006, Psychol Aging 21(1)"),
        Norm(.reachMT, .control, mean25: 0.38, sd25: 0.06, slope: 0.0025, tauYears: 16,
             source: "Reach movement slowing: Ketcham and Stelmach 2001"),
        Norm(.rtTau, .consistency, mean25: 0.040, sd25: 0.015, slope: 0.0006, tauYears: 18,
             source: "Ex-Gaussian tau rises with age: West et al. 2002"),
        Norm(.rtCV, .consistency, mean25: 0.14, sd25: 0.035, slope: 0.0012, tauYears: 18,
             source: "Intra-individual variability: Hultsch et al. 2002"),
        Norm(.eccSlope, .speed, mean25: 0.10, sd25: 0.04, slope: 0.0015, tauYears: 22,
             source: "Useful field of view narrowing: Ball et al. 1988"),
        Norm(.peakSpeed, .control, mean25: 1.90, sd25: 0.30, slope: -0.007, tauYears: 20,
             source: "Peak reach velocity: Ketcham and Stelmach 2001"),
        Norm(.pathEfficiency, .control, mean25: 0.95, sd25: 0.02, slope: -0.0006, tauYears: 22,
             source: "Prior, straightness of reach"),
        Norm(.smoothness, .control, mean25: -6.0, sd25: 0.6, slope: -0.02, tauYears: 20,
             source: "LDLJ metric: Balasubramanian et al. 2015"),
        Norm(.choiceRT, .decision, mean25: 0.43, sd25: 0.05, slope: 0.0025, accel: 0.00003, tauYears: 13,
             source: "Choice RT age curve: Der and Deary 2006"),
        Norm(.decisionTime, .decision, mean25: 0.13, sd25: 0.04, slope: 0.0010, tauYears: 18,
             source: "Choice minus simple RT, derived"),
        Norm(.commissionRate, .decision, mean25: 0.06, sd25: 0.04, slope: 0.0006, tauYears: 26,
             source: "Go/no-go errors: Bedard et al. 2002"),
        Norm(.omissionRate, nil, mean25: 0.02, sd25: 0.03, slope: 0.0002, tauYears: 99,
             source: "Quality flag only"),
        Norm(.dPrime, .decision, mean25: 3.2, sd25: 0.6, slope: -0.012, tauYears: 22,
             source: "Signal detection on go/no-go"),
        Norm(.corsiSpan, .memory, mean25: 6.2, sd25: 1.0, slope: -0.030, accel: -0.0004, tauYears: 16,
             source: "Corsi span norms: Kessels et al. 2000, 2008"),
        Norm(.corsiTotal, .memory, mean25: 52, sd25: 16, slope: -0.45, accel: -0.004, tauYears: 17,
             source: "Corsi total score: Kessels et al. 2008"),
        Norm(.corsiTapInterval, nil, mean25: 0.55, sd25: 0.12, slope: 0.004, tauYears: 99,
             source: "Display only"),
        Norm(.pursuitRMS, .control, mean25: 4.0, sd25: 1.0, slope: 0.045, accel: 0.0006, tauYears: 16,
             source: "Prior values, needs calibration"),
        Norm(.pursuitLag, .speed, mean25: 120, sd25: 30, slope: 1.5, tauYears: 18,
             source: "Visuomotor delay, prior values"),
        Norm(.pursuitOnTarget, nil, mean25: 0.55, sd25: 0.15, slope: -0.004, tauYears: 99,
             source: "Display only, redundant with tracking error"),
        Norm(.pursuitGain, nil, mean25: 1.0, sd25: 0.08, slope: -0.0005, tauYears: 99,
             source: "Display only"),
    ])
}
