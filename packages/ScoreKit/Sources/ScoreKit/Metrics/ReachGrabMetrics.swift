/// Scary Balance: how far the participant reaches and leans, and how still they hold when the creature passes.
/// Spec: specs/games/reach-grab.md.
public enum ReachGrabMetrics: MetricExtractor {
    public static let game = Game.reach
    /// A freeze is broken when the head travels further than this from where it was when the freeze began.
    public static let freezeBreakCm = 8.0

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
        // Freezes are scored on their own tracking gap, so a clean freeze in a missed reach still counts.
        let freezes = session.scored(.reachGrab).flatMap(\.reachGrabTrials).compactMap(\.freeze)
            .filter { $0.trackingGapMs <= TrialQuality.maxGapMs }
        if let m = freezes.map(\.headSwayCmS).robustMedian(.freezeSwayCmS) { out.append(m) }
        if let m = freezes.compactMap(\.handDriftCm).robustMedian(.freezeHandDriftCm) { out.append(m) }
        if !freezes.isEmpty {
            let held = freezes.filter(\.held).count
            out.append(MetricValue(.freezeHeldRate, Double(held) / Double(freezes.count), n: freezes.count,
                                   sem: GateMetrics.binomialSE(held, freezes.count)))
        }
        return (out, q)
    }
}
