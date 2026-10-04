/// Stick Drop: catch a falling leaf from a row hung across the view. Spec: specs/games/pendulum.md.
public enum PendulumMetrics: MetricExtractor {
    public static let game = Game.pendulum
    /// A grasp closing faster than this after release is a guess, not a reaction.
    public static let anticipationS = 0.10
    public static let g = 9.81
    /// Gravity ramps from 0.25 to 1 g over the scored block. Slow falls can be tracked instead of reacted to,
    /// so catch latency uses only the fast end of the ramp. Pre-0.4 sessions have no scale and fall at 1 g.
    public static let latencyMinScale = 0.75

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var latencies: [Double] = [], ecc: [Double] = [], eccLatency: [Double] = []
        var catches = 0, attempts = 0, fastDrops = 0
        for trial in session.scored(.pendulum).flatMap(\.pendulumTrials) where q.count(gapMs: trial.trackingGapMs) {
            let fast = (trial.gravityScale ?? 1) >= latencyMinScale
            switch trial.outcome {
            case .anticipation: continue
            case .drop:
                attempts += 1
                if fast { fastDrops += 1 }
            case .catch:
                guard let c = trial.catchT else { continue }
                let latency = c - trial.releaseT
                guard latency >= anticipationS else { continue }
                attempts += 1; catches += 1
                if fast { latencies.append(latency) }
                if let e = trial.eccentricityDeg { ecc.append(e / 90); eccLatency.append(latency) }
            }
        }
        var out: [MetricValue] = []
        if let m = catchLatency(latencies, drops: fastDrops) {
            out.append(m)
            // Ruler-drop equivalent at 1 g. Stick Drop scales gravity, so the observed fall is not comparable.
            out.append(MetricValue(.catchDropCm, rulerDropCm(latency: m.value), n: m.n))
        }
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

    /// Median catch latency with drops ranked slower than every catch, so a player who drops the hard leaves
    /// does not look fast on the easy ones. Nil when half or more of the attempts were drops.
    static func catchLatency(_ latencies: [Double], drops: Int) -> MetricValue? {
        let kept = Stats.trimOutliers(latencies)
        let n = kept.count + drops
        guard !kept.isEmpty, drops * 2 < n else { return nil }
        let ranked = kept.sorted() + Array(repeating: Double.infinity, count: drops)
        guard let m = Stats.median(ranked), m.isFinite else { return nil }
        return MetricValue(.catchLatency, m, n: n, sem: Stats.semMedian(kept))
    }

    /// Free-fall distance for a latency. The classic ruler drop conversion d = g t^2 / 2.
    public static func rulerDropCm(latency: Double) -> Double { 0.5 * g * latency * latency * 100 }
}
