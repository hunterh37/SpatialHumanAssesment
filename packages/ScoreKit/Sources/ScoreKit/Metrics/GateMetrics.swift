/// Gate: go/no-go choice reach. Spec: specs/games/gate.md.
/// `decision_time` needs Spark's RT and is derived in `ScoreEngine`.
public enum GateMetrics: MetricExtractor {
    public static let game = Game.gate

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var kept: [ReactionTrial] = []
        for trial in session.scored(.choiceRT).flatMap(\.reactionTrials) where q.count(gapMs: trial.trackingGapMs) {
            kept.append(trial)
        }
        var out: [MetricValue] = []
        if let m = kept.compactMap({ ReactionTiming($0)?.rt }).robustMedian(.choiceRT) { out.append(m) }

        let go = kept.filter { $0.kind == .go }
        let nogo = kept.filter { $0.kind == .nogo }
        let hits = go.filter { $0.outcome == .hit }.count
        let misses = go.filter { $0.outcome == .miss }.count
        let faNogo = nogo.filter { $0.outcome == .falseAlarm }.count
        let faAll = kept.filter { $0.outcome == .falseAlarm }.count

        if !kept.isEmpty {
            out.append(MetricValue(.commissionRate, Double(faAll) / Double(kept.count), n: kept.count,
                                   sem: binomialSE(faAll, kept.count)))
        }
        if !go.isEmpty {
            out.append(MetricValue(.omissionRate, Double(misses) / Double(go.count), n: go.count,
                                   sem: binomialSE(misses, go.count)))
        }
        if let d = Stats.dPrime(hits: hits, goTrials: go.count, falseAlarms: faNogo, nogoTrials: nogo.count) {
            out.append(MetricValue(.dPrime, d, n: kept.count))
        }
        return (out, q)
    }

    /// Agresti-Coull style standard error, never zero.
    static func binomialSE(_ k: Int, _ n: Int) -> Double {
        let p = (Double(k) + 1) / (Double(n) + 2)
        return (p * (1 - p) / Double(n + 2)).squareRoot()
    }
}
