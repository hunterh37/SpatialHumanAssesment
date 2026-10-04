/// Stick Drop: catch a falling leaf from a row hung across the view. Spec: specs/games/pendulum.md.
public enum PendulumMetrics: MetricExtractor {
    public static let game = Game.pendulum
    /// A grasp closing faster than this after release is a guess, not a reaction.
    public static let anticipationS = 0.10
    public static let g = 9.81

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var latencies: [Double] = [], drops: [Double] = [], ecc: [Double] = [], eccLatency: [Double] = []
        var catches = 0, attempts = 0
        for trial in session.scored(.pendulum).flatMap(\.pendulumTrials) where q.count(gapMs: trial.trackingGapMs) {
            switch trial.outcome {
            case .anticipation: continue
            case .drop: attempts += 1
            case .catch:
                guard let c = trial.catchT else { continue }
                let latency = c - trial.releaseT
                guard latency >= anticipationS else { continue }
                attempts += 1; catches += 1
                latencies.append(latency)
                // Ruler-drop equivalent at 1 g. Stick Drop scales gravity, so the observed fall is not comparable.
                drops.append(rulerDropCm(latency: latency))
                if let e = trial.eccentricityDeg { ecc.append(e / 90); eccLatency.append(latency) }
            }
        }
        var out: [MetricValue] = []
        if let m = latencies.robustMedian(.catchLatency) { out.append(m) }
        if let m = drops.robustMedian(.catchDropCm) { out.append(m) }
        // Useful field of view: catch latency on the falling leaf's angle from head forward, per 90 degrees.
        if ecc.count >= 6, let line = Stats.ols(ecc, eccLatency) {
            out.append(MetricValue(.catchEccSlope, line.slope, n: ecc.count, sem: line.slopeSE))
        }
        if attempts > 0 {
            out.append(MetricValue(.catchRate, Double(catches) / Double(attempts), n: attempts,
                                   sem: GateMetrics.binomialSE(catches, attempts)))
        }
        return (out, q)
    }

    /// Free-fall distance for a latency. The classic ruler drop conversion d = g t^2 / 2.
    public static func rulerDropCm(latency: Double) -> Double { 0.5 * g * latency * latency * 100 }
}
