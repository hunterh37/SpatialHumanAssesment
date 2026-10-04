import Foundation

/// Spatial Age: a functional age in years from the session metrics.
///
/// 1. Each metric value is inverted through its norm curve to a metric age.
/// 2. Its uncertainty in years = measurement SE / curve slope, combined with the norm's residual
///    error `tau`. Steep curves and many trials give tight estimates.
/// 3. Metrics fuse into domain ages by inverse-variance weighting. Metrics in a domain are correlated,
///    so the fused variance is inflated by the design effect 1 + (k - 1) rho.
/// 4. Domain ages fuse the same way, then combine with a prior centered on chronological age.
///    The prior shrinks thin evidence toward the calendar, as any aging clock must.
public struct SpatialAgeModel: Sendable {
    public var norms: NormTable
    public var ageRange: ClosedRange<Double> = 18...95
    /// Correlation assumed among metrics inside a domain and among domains.
    public var withinDomainRho = 0.5
    public var betweenDomainRho = 0.3
    /// SD of the chronological prior, years.
    public var priorSD = 9.0
    /// Metrics with residual error above this do not enter the model.
    public var maxTauYears = 50.0

    public init(norms: NormTable = .provisional) { self.norms = norms }

    public struct Estimate: Codable, Sendable {
        public var age: Double
        public var sd: Double
    }

    public struct MetricAge: Sendable {
        public var id: MetricID
        public var domain: Domain
        public var estimate: Estimate
    }

    public func metricAge(_ m: MetricValue) -> MetricAge? {
        guard let norm = norms[m.id], let domain = norm.domain, norm.tauYears <= maxTauYears else { return nil }
        let age = norm.age(for: m.value, range: ageRange)
        let rate = abs(norm.rate(at: age))
        guard rate > 0 else { return nil }
        // Without a trial-level SE, assume a third of the between-person SD.
        let sem = m.sem ?? norm.sd25 / 3
        let measYears = sem / rate
        let sd = (measYears * measYears + norm.tauYears * norm.tauYears).squareRoot()
        return MetricAge(id: m.id, domain: domain, estimate: Estimate(age: age, sd: sd))
    }

    static func fuse(_ xs: [Estimate], rho: Double) -> Estimate? {
        guard !xs.isEmpty else { return nil }
        let w = xs.map { 1 / ($0.sd * $0.sd) }
        let wsum = w.reduce(0, +)
        let age = zip(xs, w).reduce(0) { $0 + $1.0.age * $1.1 } / wsum
        let design = 1 + Double(xs.count - 1) * rho
        return Estimate(age: age, sd: (design / wsum).squareRoot())
    }

    public struct Result: Sendable {
        public var metricAges: [MetricAge]
        public var domainAges: [Domain: Estimate]
        /// Evidence only, no prior.
        public var evidence: Estimate?
        /// Posterior with the chronological prior. Equals `evidence` when age is unknown.
        public var spatialAge: Estimate?
    }

    public func estimate(_ metrics: [MetricValue], chronologicalAge: Double?) -> Result {
        let ages = metrics.compactMap(metricAge)
        var domains: [Domain: Estimate] = [:]
        for d in Domain.allCases {
            if let e = Self.fuse(ages.filter { $0.domain == d }.map(\.estimate), rho: withinDomainRho) {
                domains[d] = e
            }
        }
        let evidence = Self.fuse(Domain.allCases.compactMap { domains[$0] }, rho: betweenDomainRho)
        var posterior = evidence
        if let e = evidence, let chrono = chronologicalAge {
            let wE = 1 / (e.sd * e.sd), wP = 1 / (priorSD * priorSD)
            let age = (e.age * wE + chrono * wP) / (wE + wP)
            posterior = Estimate(age: min(max(age, ageRange.lowerBound), ageRange.upperBound),
                                 sd: (1 / (wE + wP)).squareRoot())
        }
        return Result(metricAges: ages, domainAges: domains, evidence: evidence, spatialAge: posterior)
    }
}
