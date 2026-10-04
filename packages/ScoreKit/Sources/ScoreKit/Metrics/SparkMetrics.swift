/// Spark: simple reach reaction. Spec: specs/games/spark.md.
public enum SparkMetrics: MetricExtractor {
    public static let game = Game.spark

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var timings: [(ReactionTiming, ReactionTrial)] = []
        for trial in session.scored(.simpleRT).flatMap(\.reactionTrials) {
            guard q.count(gapMs: trial.trackingGapMs), let t = ReactionTiming(trial) else { continue }
            timings.append((t, trial))
        }
        var out: [MetricValue] = []
        let rts = timings.map(\.0.rt)
        if let m = rts.robustMedian(.reachRT) { out.append(m) }
        if let m = timings.map(\.0.mt).robustMedian(.reachMT) { out.append(m) }

        // Tau is the tail, so it is fit on untrimmed RTs (already bounded by ReactionTiming).
        if let ex = Stats.exGaussian(rts) {
            out.append(MetricValue(.rtTau, ex.tau, n: rts.count))
        }
        let trimmed = Stats.trimOutliers(rts)
        if trimmed.count > 4, let sd = Stats.sd(trimmed), let mean = Stats.mean(trimmed), mean > 0 {
            out.append(MetricValue(.rtCV, sd / mean, n: trimmed.count))
        }

        // Total reach time on eccentricity in units of 90 degrees.
        let ecc = timings.map { $0.1.eccentricityDeg / 90 }
        let total = timings.map { $0.0.rt + $0.0.mt }
        if let line = Stats.ols(ecc, total) {
            out.append(MetricValue(.eccSlope, line.slope, n: ecc.count, sem: line.slopeSE))
        }

        let reaches = timings.compactMap(\.0.reach)
        if let m = reaches.map(\.peakSpeed).robustMedian(.peakSpeed) { out.append(m) }
        if let m = reaches.map(\.pathEfficiency).robustMedian(.pathEfficiency) { out.append(m) }
        if let m = reaches.map(\.ldlj).robustMedian(.smoothness) { out.append(m) }
        return (out, q)
    }
}
