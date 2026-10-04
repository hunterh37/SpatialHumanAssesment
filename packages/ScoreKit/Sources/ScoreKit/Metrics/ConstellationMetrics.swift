/// Constellation: 3D Corsi block tapping. Spec: specs/games/constellation.md.
public enum ConstellationMetrics: MetricExtractor {
    public static let game = Game.constellation

    public static func extract(_ session: Session) -> (metrics: [MetricValue], quality: TrialQuality) {
        var q = TrialQuality()
        let trials = session.scored(.corsi).flatMap(\.corsiTrials)
        for _ in trials { _ = q.count(gapMs: 0) }
        guard !trials.isEmpty else { return ([], q) }

        let correct = trials.filter(\.correct)
        let span = correct.map(\.span).max() ?? 0
        var out = [
            MetricValue(.corsiSpan, Double(span), n: trials.count, sem: 0.5),
            // Total score = span x number of correct sequences (Kessels et al. 2008).
            MetricValue(.corsiTotal, Double(span * correct.count), n: trials.count),
        ]
        let gaps = correct.flatMap { t -> [Double] in
            guard let taps = t.tapT, taps.count > 1 else { return [] }
            return zip(taps.dropFirst(), taps).map { $0 - $1 }
        }
        if let m = gaps.robustMedian(.corsiTapInterval) { out.append(m) }
        return (out, q)
    }

    /// Replays a block's span from its trials, as the staircase in the spec defines it.
    public static func replaySpan(_ trials: [CorsiTrial]) -> Int {
        trials.filter { $0.response == $0.sequence }.map(\.span).max() ?? 0
    }
}
