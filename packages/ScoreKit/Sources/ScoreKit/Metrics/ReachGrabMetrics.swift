/// Reach and grab: how far the participant reaches and leans with feet planted. Spec: specs/games/reach-grab.md.
public enum ReachGrabMetrics: MetricExtractor {
    public static let game = Game.reach

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var kept: [ReachGrabTrial] = []
        for trial in session.scored(.reachGrab).flatMap(\.reachGrabTrials) where q.count(gapMs: trial.trackingGapMs) {
            kept.append(trial)
        }
        let grabs = kept.filter { $0.outcome == .grab }

        var out: [MetricValue] = []
        // Furthest object touched, shoulder to object center.
        if let furthest = grabs.map({ $0.distanceM * 100 }).max() {
            out.append(MetricValue(.reachMaxCm, furthest, n: grabs.count))
        }
        // Largest head travel at a grab. A maximum, so it has no trial-level standard error.
        let leans = grabs.compactMap(\.leanM).map { $0 * 100 }
        if let deepest = leans.max() {
            out.append(MetricValue(.reachLeanCm, deepest, n: leans.count))
        }
        if !kept.isEmpty {
            out.append(MetricValue(.reachGrabRate, Double(grabs.count) / Double(kept.count), n: kept.count,
                                   sem: GateMetrics.binomialSE(grabs.count, kept.count)))
        }
        return (out, q)
    }
}
