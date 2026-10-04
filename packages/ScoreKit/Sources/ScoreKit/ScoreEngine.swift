import Foundation

/// Report for one session. Stable JSON contract for the app, ingest, dashboard and showcase.
public struct ScoreReport: Codable, Sendable {
    public struct MetricResult: Codable, Sendable {
        public var id: MetricID
        public var label: String
        public var unit: String
        public var game: Game
        public var domain: Domain?
        public var value: Double
        public var n: Int
        public var sem: Double?
        public var metricAge: Double?
        public var metricAgeSD: Double?
        /// Percentile against the age-25 reference, 100 = best.
        public var peakScore: Double?
    }

    public struct DomainResult: Codable, Sendable {
        public var domain: Domain
        public var title: String
        /// 0 to 100 against the age-25 reference.
        public var score: Double
        public var age: Double?
        public var ageSD: Double?
        public var metrics: [MetricID]
    }

    public struct GameResult: Codable, Sendable {
        public var game: Game
        public var title: String
        public var played: Bool
        public var trialsScored: Int
        public var trialsKept: Int
        public var score: Double?
        public var headline: MetricID?
    }

    public struct Quality: Codable, Sendable {
        public var validTrialRate: Double?
        public var worstGapMs: Double
        public var gamesPlayed: Int
        public var usable: Bool
        public var flags: [String]
    }

    public var engineVersion: String
    public var normsVersion: String
    public var sessionId: String
    public var participantCode: String
    public var startedAt: Date
    public var chronologicalAge: Double?
    public var spatialAge: Double?
    public var spatialAgeSD: Double?
    /// 80 percent interval.
    public var spatialAgeLow: Double?
    public var spatialAgeHigh: Double?
    /// Fused metric evidence before the chronological prior.
    public var evidenceAge: Double?
    /// Spatial Age minus chronological age. Negative is younger.
    public var ageGap: Double?
    public var domains: [DomainResult]
    public var games: [GameResult]
    public var metrics: [MetricResult]
    public var quality: Quality
}

/// Session in, `ScoreReport` out. Pure function of the session and the norm table.
public struct ScoreEngine: Sendable {
    public static let version = "0.4.0"
    public static let extractors: [any MetricExtractor.Type] = [
        PendulumMetrics.self, SparkMetrics.self, GateMetrics.self, ConstellationMetrics.self, OrbitMetrics.self,
        ReachGrabMetrics.self, WallMetrics.self, ColorDotsMetrics.self,
    ]
    /// Sessions under this valid trial rate are flagged unusable (specs/features.md).
    public static let minValidRate = 0.7

    public var model: SpatialAgeModel
    public init(norms: NormTable = .provisional) { model = SpatialAgeModel(norms: norms) }

    public func measure(_ session: Session) -> (metrics: [MetricValue], quality: [Game: TrialQuality]) {
        var metrics: [MetricValue] = []
        var quality: [Game: TrialQuality] = [:]
        for ex in Self.extractors {
            let (m, q) = ex.extract(session)
            metrics += m
            quality[ex.game] = q
        }
        // Cross-game: decision time = choice RT - simple RT.
        if let c = metrics[.choiceRT], let s = metrics[.reachRT] {
            let sem = (c.sem ?? 0) * (c.sem ?? 0) + (s.sem ?? 0) * (s.sem ?? 0)
            metrics.append(MetricValue(.decisionTime, c.value - s.value, n: min(c.n, s.n),
                                       sem: sem > 0 ? sem.squareRoot() : nil))
        }
        return (metrics.sorted { $0.id < $1.id }, quality)
    }

    public func score(_ session: Session) -> ScoreReport {
        let (metrics, quality) = measure(session)
        let chrono = session.participant.ageYears > 0 ? session.participant.ageYears : nil
        let est = model.estimate(metrics, chronologicalAge: chrono)
        let norms = model.norms

        let metricResults = metrics.map { m -> ScoreReport.MetricResult in
            let norm = norms[m.id]
            let age = est.metricAges.first { $0.id == m.id }
            return .init(id: m.id, label: m.id.label, unit: m.id.unit, game: m.id.game, domain: norm?.domain,
                         value: m.value, n: m.n, sem: m.sem, metricAge: age?.estimate.age,
                         metricAgeSD: age?.estimate.sd,
                         peakScore: norm.map { Self.percentile(z: $0.agingZ(m.value)) })
        }

        let domains = Domain.allCases.compactMap { d -> ScoreReport.DomainResult? in
            let inDomain = metricResults.filter { $0.domain == d && $0.metricAge != nil }
            let scores = inDomain.compactMap(\.peakScore)
            guard let mean = Stats.mean(scores) else { return nil }
            return .init(domain: d, title: d.title, score: mean, age: est.domainAges[d]?.age,
                         ageSD: est.domainAges[d]?.sd, metrics: inDomain.map(\.id))
        }

        let games = Game.allCases.map { g -> ScoreReport.GameResult in
            let q = quality[g] ?? TrialQuality()
            let scored = metricResults.filter { $0.game == g && $0.metricAge != nil }.compactMap(\.peakScore)
            return .init(game: g, title: g.title, played: q.total > 0, trialsScored: q.total, trialsKept: q.kept,
                         score: Stats.mean(scored), headline: Self.headline[g])
        }

        var total = TrialQuality()
        quality.values.forEach { total.merge($0) }
        var flags: [String] = []
        let validRate = total.validRate
        if let r = validRate, r < Self.minValidRate { flags.append("valid_trial_rate_below_\(Self.minValidRate)") }
        let played = games.filter(\.played).count
        if played < 3 { flags.append("fewer_than_3_games") }
        if let a = metrics[.catchRate], a.value < 0.5 { flags.append("pendulum_catch_rate_low") }
        if let o = metrics[.omissionRate], o.value > 0.2 { flags.append("gate_omissions_high") }

        let sa = est.spatialAge
        return ScoreReport(
            engineVersion: Self.version, normsVersion: norms.version, sessionId: session.sessionId,
            participantCode: session.participant.code, startedAt: session.startedAt, chronologicalAge: chrono,
            spatialAge: sa?.age, spatialAgeSD: sa?.sd,
            spatialAgeLow: sa.map { $0.age - 1.2816 * $0.sd }, spatialAgeHigh: sa.map { $0.age + 1.2816 * $0.sd },
            evidenceAge: est.evidence?.age,
            ageGap: zip2(sa?.age, chrono).map { $0 - $1 },
            domains: domains, games: games, metrics: metricResults,
            quality: .init(validTrialRate: validRate, worstGapMs: total.worstGapMs, gamesPlayed: played,
                           usable: (validRate ?? 0) >= Self.minValidRate && played >= 3,
                           flags: flags))
    }

    /// Metric shown large on each game card.
    public static let headline: [Game: MetricID] = [
        .pendulum: .catchDropCm, .spark: .reachRT, .gate: .decisionTime,
        .constellation: .corsiSpan, .orbit: .pursuitRMS,
        .reach: .reachLeanCm, .wall: .wallSwayCmS, .dots: .dotsSpan,
    ]

    /// 0 to 100, higher is better, from an aging z-score.
    static func percentile(z: Double) -> Double { min(max(100 * (1 - Stats.phi(z)), 1), 99) }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

public extension ScoreReport {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
