/// Pendulum: catch a ballistically falling bob. Spec: specs/games/pendulum.md.
public enum PendulumMetrics: MetricExtractor {
    public static let game = Game.pendulum
    /// A grasp closing faster than this after release is a guess, not a reaction.
    public static let anticipationS = 0.10
    public static let g = 9.81

    public static func extract(_ session: Session) -> (metrics: [Measurement], quality: TrialQuality) {
        var q = TrialQuality()
        var latencies: [Double] = [], drops: [Double] = []
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
                if let d = trial.dropM { drops.append(d * 100) }
            }
        }
        var out: [Measurement] = []
        if let m = latencies.robustMedian(.catchLatency) { out.append(m) }
        if let m = drops.robustMedian(.catchDropCm) { out.append(m) }
        if attempts > 0 {
            out.append(Measurement(.catchRate, Double(catches) / Double(attempts), n: attempts,
                                   sem: GateMetrics.binomialSE(catches, attempts)))
        }
        return (out, q)
    }

    /// Free-fall distance for a latency. The classic ruler drop conversion d = g t^2 / 2.
    public static func rulerDropCm(latency: Double) -> Double { 0.5 * g * latency * latency * 100 }
}
