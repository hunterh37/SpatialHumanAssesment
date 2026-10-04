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
    public static let provisional = NormTable(version: "prior-0.4", norms: [
        Norm(.catchLatency, .speed, mean25: 0.19, sd25: 0.025, slope: 0.0004, accel: 0.000012, tauYears: 20,
             source: "Ruler drop RT level: Eckner et al. 2010. Simple RT shows little slowing before ~50: Der and Deary 2006, UK HALS n=7130"),
        Norm(.catchDropCm, nil, mean25: 17.7, sd25: 4.5, slope: 0.17, tauYears: 99,
             source: "Display only. Derived from catch latency, d = g t^2 / 2"),
        Norm(.catchRate, .control, mean25: 0.95, sd25: 0.05, slope: -0.0015, accel: -0.00003, tauYears: 26,
             source: "Prior, no published reference for this task"),
        Norm(.catchEccSlope, .speed, mean25: 0.03, sd25: 0.03, slope: 0.0008, tauYears: 26,
             source: "Stick Drop field of view cost. Direction from useful field of view narrowing, Ball et al. 1988. Placeholder level"),
        Norm(.reachRT, .speed, mean25: 0.30, sd25: 0.04, slope: 0.0005, accel: 0.00002, tauYears: 22,
             source: "Simple RT nearly flat until ~50: Der and Deary 2006; Dykiert et al. 2012. Wide tau: Spatial Tracking onset includes cue localization"),
        Norm(.reachMT, .control, mean25: 0.38, sd25: 0.06, slope: 0.0025, tauYears: 16,
             source: "Reach movement slowing: Ketcham and Stelmach 2001"),
        Norm(.rtTau, .consistency, mean25: 0.040, sd25: 0.015, slope: 0.0006, tauYears: 18,
             source: "Ex-Gaussian tau rises with age: West et al. 2002"),
        Norm(.rtCV, .consistency, mean25: 0.14, sd25: 0.035, slope: 0.0012, tauYears: 26,
             source: "Variability rises with age (Hultsch et al. 2002, extreme groups); CV is a weaker age marker than SD (Dykiert et al. 2012)"),
        Norm(.eccSlope, .speed, mean25: 0.10, sd25: 0.04, slope: 0.0015, tauYears: 22,
             source: "Useful field of view narrowing: Ball et al. 1988"),
        Norm(.peakSpeed, .control, mean25: 1.90, sd25: 0.30, slope: -0.007, tauYears: 20,
             source: "Peak reach velocity: Ketcham and Stelmach 2001"),
        Norm(.pathEfficiency, .control, mean25: 0.95, sd25: 0.02, slope: -0.0006, tauYears: 22,
             source: "Prior, straightness of reach"),
        Norm(.smoothness, .control, mean25: -6.0, sd25: 0.6, slope: -0.02, tauYears: 20,
             source: "LDLJ metric: Balasubramanian et al. 2015"),
        Norm(.choiceRT, .decision, mean25: 0.43, sd25: 0.05, slope: 0.0025, accel: 0.00003, tauYears: 20,
             source: "Choice RT slows across adulthood: Der and Deary 2006; go RT 277 ms at 18 vs 351 ms at 60-69, Communications Medicine 2025"),
        Norm(.decisionTime, .decision, mean25: 0.13, sd25: 0.04, slope: 0.0010, tauYears: 30,
             source: "Choice minus simple RT, derived. Subtraction removes shared proportional slowing, so weak"),
        Norm(.commissionRate, nil, mean25: 0.06, sd25: 0.04, slope: 0.0006, tauYears: 99,
             source: "Display only. Go/no-go false alarms do not rise with age: Cheng et al. 2019 meta-analysis; 11.6% young vs 6.6% at 70-79, Communications Medicine 2025"),
        Norm(.omissionRate, .decision, mean25: 0.01, sd25: 0.03, slope: 0.0002, accel: 0.000053, tauYears: 30,
             source: "Go/no-go omissions 1.1% (~18), 3.1% (60s), 4.9% (70s), 10.1% (80+): Communications Medicine 2025 (500 ms deadline)"),
        Norm(.dPrime, .decision, mean25: 3.2, sd25: 0.6, slope: -0.012, tauYears: 30,
             source: "Signal detection on go/no-go. Fewer false alarms offset more misses with age, so the net slope is uncertain"),
        Norm(.corsiSpan, .memory, mean25: 6.0, sd25: 1.0, slope: -0.025, tauYears: 35,
             source: "SD 1.03, r(age) = -0.46 over 21-89: Facchin et al. 2024; young level 6-7 by protocol: Kessels et al. 2000, Pagulayan et al. 2006"),
        Norm(.corsiTotal, nil, mean25: 52, sd25: 16, slope: -0.45, accel: -0.004, tauYears: 99,
             source: "Display only: same trials as span. Kessels et al. 2008"),
        Norm(.corsiTapInterval, nil, mean25: 0.55, sd25: 0.12, slope: 0.004, tauYears: 99,
             source: "Display only"),
        Norm(.pursuitRMS, .control, mean25: 4.0, sd25: 1.0, slope: 0.02, accel: 0.0006, tauYears: 30,
             source: "Direction only: older adults track with more error and lag (Neuroscience 2026; T&F 2024). Placeholder magnitude"),
        Norm(.pursuitLag, .speed, mean25: 120, sd25: 30, slope: 1.5, tauYears: 18,
             source: "Visuomotor delay, prior values"),
        Norm(.pursuitOnTarget, nil, mean25: 0.55, sd25: 0.15, slope: -0.004, tauYears: 99,
             source: "Display only, redundant with tracking error"),
        Norm(.pursuitGain, nil, mean25: 1.0, sd25: 0.08, slope: -0.0005, tauYears: 99,
             source: "Display only"),
        // Reach and grab, Hole in the wall, Color dots (v0.3). Weak priors with high tau until refit on event data.
        Norm(.reachMaxCm, nil, mean25: 75, sd25: 8, slope: -0.1, tauYears: 99,
             source: "Display only. Depends on arm length, so it is not an age marker by itself"),
        Norm(.reachLeanCm, .control, mean25: 37.0, sd25: 7.4, slope: -0.25, tauYears: 25,
             source: "Functional reach by age band, Nakhostin-Ansari et al. 2022 (PMC9422043) Table 2, parsed in code: 37.3 cm at 18-29 to 24.3 cm at 70+. Head lean is not hand reach, so calibrate"),
        Norm(.reachGrabRate, nil, mean25: 0.8, sd25: 0.1, slope: -0.003, tauYears: 99,
             source: "Display only"),
        Norm(.freezeSwayCmS, .control, mean25: 1.5, sd25: 0.5, slope: 0.018, accel: 0.0002, tauYears: 28,
             source: "Scary Balance freeze. Placeholder prior with the head-sway shape used for Hole in the Wall, held in a reach, so calibrate"),
        Norm(.freezeHandDriftCm, .control, mean25: 0.9, sd25: 0.35, slope: 0.009, tauYears: 30,
             source: "Placeholder prior, needs calibration"),
        Norm(.freezeHeldRate, nil, mean25: 0.95, sd25: 0.06, slope: -0.002, tauYears: 99,
             source: "Display only"),
        Norm(.wallSwayCmS, .control, mean25: 1.2, sd25: 0.4, slope: 0.015, accel: 0.0002, tauYears: 28,
             source: "Placeholder prior: no headset head-sway norms found. Direction from posturography sway by age band (PMC12926707). Replace after calibration"),
        Norm(.wallHandDriftCm, .control, mean25: 0.8, sd25: 0.3, slope: 0.008, tauYears: 30,
             source: "Placeholder prior, needs calibration"),
        Norm(.wallClearRate, nil, mean25: 0.9, sd25: 0.1, slope: -0.003, tauYears: 99,
             source: "Display only"),
        Norm(.wallWorstPoseCm, nil, mean25: 6, sd25: 3, slope: 0.08, tauYears: 99,
             source: "Display only. Mean hand error on the pose the participant fit worst, a mobility flag"),
        Norm(.dotsSpan, .memory, mean25: 5.0, sd25: 1.0, slope: -0.030, accel: -0.0004, tauYears: 20,
             source: "Shape from Corsi span norms (Kessels et al. 2000); recognition among decoys differs, so calibrate"),
        Norm(.dotsAccuracy, .memory, mean25: 0.85, sd25: 0.1, slope: -0.003, tauYears: 24,
             source: "Placeholder prior, needs calibration"),
        Norm(.dotsFalseRate, .decision, mean25: 0.05, sd25: 0.04, slope: 0.0006, tauYears: 26,
             source: "Shape from go/no-go commission errors: Bedard et al. 2002"),
        Norm(.dotsDecisionTime, .decision, mean25: 0.9, sd25: 0.2, slope: 0.0028, tauYears: 22,
             source: "Slope: choice RT rises 2.80 ms per year, Woods et al. 2015 (PMC4407573). Level is a placeholder"),
        Norm(.dotsSelectTime, .decision, mean25: 0.8, sd25: 0.2, slope: 0.0028, tauYears: 24,
             source: "Spatial Memory select phase, time per ball. Slope from Woods et al. 2015 choice RT. Level is a placeholder"),
    ])
}
