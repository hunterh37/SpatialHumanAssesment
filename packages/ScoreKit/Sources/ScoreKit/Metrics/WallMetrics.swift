/// Hole in the wall: hold both hands in the cutouts while a wall arrives. Spec: specs/games/wall.md.
public enum WallMetrics: MetricExtractor {
    public static let game = Game.wall
    /// A hand within this distance of its cutout center counts as in the hole.
    public static let clearRadiusM = 0.12
    /// A wall is cleared when both hands average within `clearRadiusM` over this last stretch of the hold.
    /// The game applies the rule when it logs the trial; the extractor reads the logged outcome.
    public static let clearWindowS = 0.5

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var kept: [WallTrial] = []
        for trial in session.scored(.wall).flatMap(\.wallTrials) where q.count(gapMs: trial.trackingGapMs) {
            kept.append(trial)
        }

        var out: [MetricValue] = []
        // Sway counts every kept wall, cleared or hit. A hit is not a reason to discard how still the head was.
        if let m = kept.map(\.headSwayCmS).robustMedian(.wallSwayCmS) { out.append(m) }
        // Drift is nil for a trial where no hand had two samples, so it can have fewer values than sway.
        if let m = kept.compactMap(\.handDriftCm).robustMedian(.wallHandDriftCm) { out.append(m) }
        if !kept.isEmpty {
            let cleared = kept.filter { $0.outcome == .cleared }.count
            out.append(MetricValue(.wallClearRate, Double(cleared) / Double(kept.count), n: kept.count,
                                   sem: GateMetrics.binomialSE(cleared, kept.count)))
        }
        return (out, q)
    }
}
