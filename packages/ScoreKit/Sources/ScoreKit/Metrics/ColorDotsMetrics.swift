/// Color Dots: recall of lit dots among decoys. Spec: specs/games/color-dots.md.
public enum ColorDotsMetrics: MetricExtractor {
    public static let game = Game.dots

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        var kept: [ColorDotsTrial] = []
        for trial in session.scored(.colorDots).flatMap(\.colorDotsTrials) where q.count(gapMs: trial.trackingGapMs) {
            kept.append(trial)
        }
        guard !kept.isEmpty else { return ([], q) }
        var out: [MetricValue] = []

        // Span: the largest set recalled perfectly, every lit dot touched and nothing else.
        let perfect = kept.filter { $0.hits == $0.setSize && $0.falseTaps == 0 }
        if let span = perfect.map(\.setSize).max() {
            out.append(MetricValue(.dotsSpan, Double(span), n: kept.count, sem: 0.5))
        }

        // Accuracy: hits minus false taps as a share of the set, never below zero.
        let accuracy = kept.filter { $0.setSize > 0 }.map { Double(max(0, $0.hits - $0.falseTaps)) / Double($0.setSize) }
        if let mean = Stats.mean(accuracy) {
            let sem = Stats.sd(accuracy).map { $0 / Double(accuracy.count).squareRoot() }
            out.append(MetricValue(.dotsAccuracy, mean, n: accuracy.count, sem: sem))
        }

        // False rate: the share of touches that landed on a decoy. The touches are the observations, so n counts them.
        let falseTaps = kept.reduce(0) { $0 + $1.falseTaps }
        let touches = kept.reduce(0) { $0 + $1.hits + $1.falseTaps }
        if touches > 0 {
            out.append(MetricValue(.dotsFalseRate, Double(falseTaps) / Double(touches), n: touches,
                                   sem: GateMetrics.binomialSE(falseTaps, touches)))
        }

        // Decision time: from the grey scene to the first touch, in trials that had one.
        let firstTouch = kept.compactMap { t in t.touchT.first.map { $0 - t.recallStartT } }
        if let m = firstTouch.robustMedian(.dotsDecisionTime) { out.append(m) }
        return (out, q)
    }
}
