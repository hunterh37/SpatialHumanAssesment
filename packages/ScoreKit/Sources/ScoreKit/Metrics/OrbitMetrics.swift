/// Orbit: 3D smooth pursuit. Spec: specs/games/orbit.md.
public enum OrbitMetrics: MetricExtractor {
    public static let game = Game.orbit
    /// The first second is target acquisition and is not scored.
    public static let acquisitionS = 1.0
    /// Target sphere radius. Inside it counts as on target.
    public static let onTargetM = 0.04
    /// Lag search window and step.
    public static let maxLagS = 0.5
    public static let lagStepS = 0.005
    /// Missing samples are masked, so a trial survives longer gaps than reach trials do.
    public static let maxGapMs = 300.0

    struct TrialResult { var rms, onTarget, lag, gain: Double; var n: Int }

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var results: [TrialResult] = []
        for trial in session.scored(.pursuit).flatMap(\.pursuitTrials) where q.count(gapMs: trial.trackingGapMs, limit: maxGapMs) {
            if let r = score(trial) { results.append(r) }
        }
        guard !results.isEmpty else { return ([], q) }
        let n = results.reduce(0) { $0 + $1.n }
        func pooled(_ id: MetricID, _ f: (TrialResult) -> Double) -> MetricValue {
            let xs = results.map(f)
            let sem = Stats.sd(xs).map { $0 / Double(xs.count).squareRoot() }
            return MetricValue(id, Stats.mean(xs)!, n: n, sem: sem)
        }
        return ([
            pooled(.pursuitRMS) { $0.rms * 100 },
            pooled(.pursuitLag) { $0.lag * 1000 },
            pooled(.pursuitOnTarget) { $0.onTarget },
            pooled(.pursuitGain) { $0.gain },
        ], q)
    }

    static func score(_ trial: PursuitTrial) -> TrialResult? {
        var ts: [Double] = [], fs: [V3] = [], targets: [V3] = []
        for i in trial.t.indices {
            let rel = trial.t[i] - trial.startT
            guard rel >= acquisitionS, let f = trial.finger[i] else { continue }
            ts.append(rel); fs.append(f); targets.append(trial.target[i])
        }
        guard ts.count >= 30 else { return nil }
        let err = zip(fs, targets).map { $0.distance(to: $1) }
        let rms = (err.reduce(0) { $0 + $1 * $1 } / Double(err.count)).squareRoot()
        let onTarget = Double(err.filter { $0 <= onTargetM }.count) / Double(err.count)

        // Lag: shift the analytic path back in time until it best matches the fingertip.
        var bestLag = 0.0, bestErr = Double.infinity
        var lag = 0.0
        while lag <= maxLagS {
            var sum = 0.0
            for (t, f) in zip(ts, fs) { sum += f.distance(to: trial.path.position(at: t - lag)) }
            if sum < bestErr { bestErr = sum; bestLag = lag }
            lag += lagStepS
        }

        // Gain: least-squares projection of fingertip velocity onto lag-aligned target velocity.
        // Tremor and jitter are uncorrelated with the target, so they average out instead of inflating gain.
        var num = 0.0, den = 0.0
        for i in 1..<ts.count where ts[i] - ts[i - 1] < 0.1 {
            let dt = ts[i] - ts[i - 1]
            let vf = (fs[i] - fs[i - 1]) / dt
            let vt = (trial.path.position(at: ts[i] - bestLag) - trial.path.position(at: ts[i - 1] - bestLag)) / dt
            num += vf.dot(vt); den += vt.dot(vt)
        }
        return TrialResult(rms: rms, onTarget: onTarget, lag: bestLag, gain: den > 0 ? num / den : 0, n: ts.count)
    }
}
