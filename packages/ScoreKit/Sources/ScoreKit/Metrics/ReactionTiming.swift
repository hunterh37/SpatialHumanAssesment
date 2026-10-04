/// Reaction and movement times for one hit, preferring trace-based onset over the device-reported `move_t`.
struct ReactionTiming {
    /// RTs faster than this are anticipations, slower are lapses. Both are dropped from timing stats.
    static let minRT = 0.10
    static let maxRT = 1.50

    var rt: Double
    var mt: Double
    var reach: Kinematics.Reach?

    init?(_ trial: ReactionTrial) {
        guard trial.outcome == .hit, let contact = trial.contactT else { return nil }
        let kin = trial.trace.flatMap(Kinematics.init)
        guard let onset = kin?.onset(after: trial.spawnT, before: contact) ?? trial.moveT else { return nil }
        let rt = onset - trial.spawnT
        guard rt >= Self.minRT, rt <= Self.maxRT, contact > onset else { return nil }
        self.rt = rt
        self.mt = contact - onset
        self.reach = kin?.reach(from: onset, to: contact)
    }
}

extension Array where Element == Double {
    /// Median of the outlier-trimmed values with its standard error.
    func robustMedian(_ id: MetricID) -> Measurement? {
        let kept = Stats.trimOutliers(self)
        guard let m = Stats.median(kept) else { return nil }
        return Measurement(id, m, n: kept.count, sem: Stats.semMedian(kept))
    }
}
