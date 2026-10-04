import Foundation

/// Pace of aging: years of Spatial Age gained per calendar year, across sessions.
///
/// Weighted least squares of Spatial Age on elapsed time, weights 1 / sd^2, then shrunk toward 1.0
/// (aging at the calendar rate) with a prior SD of 0.5. Short windows carry little evidence, so the
/// pace stays near 1.0 until months of sessions accumulate.
public enum PaceOfAging {
    public struct Point: Codable, Sendable {
        public var date: Date
        public var spatialAge: Double
        public var sd: Double
        public init(date: Date, spatialAge: Double, sd: Double) {
            self.date = date; self.spatialAge = spatialAge; self.sd = sd
        }
    }

    public struct Pace: Codable, Sendable {
        /// 1.0 = calendar rate. Below 1 is slower aging.
        public var pace: Double
        public var sd: Double
        /// Unshrunk WLS slope, for audit.
        public var rawSlope: Double
        public var sessions: Int
        public var windowDays: Double
    }

    public static let minSessions = 3
    public static let minWindowDays = 28.0
    public static let priorSD = 0.5

    public static func estimate(_ points: [Point]) -> Pace? {
        guard points.count >= minSessions,
              let first = points.map(\.date).min(), let last = points.map(\.date).max() else { return nil }
        let window = last.timeIntervalSince(first) / 86_400
        guard window >= minWindowDays else { return nil }

        let xs = points.map { $0.date.timeIntervalSince(first) / (365.25 * 86_400) }
        let ys = points.map(\.spatialAge)
        let ws = points.map { 1 / max($0.sd * $0.sd, 0.25) }
        let wsum = ws.reduce(0, +)
        let mx = zip(xs, ws).reduce(0) { $0 + $1.0 * $1.1 } / wsum
        let my = zip(ys, ws).reduce(0) { $0 + $1.0 * $1.1 } / wsum
        var sxx = 0.0, sxy = 0.0
        for i in xs.indices {
            sxx += ws[i] * (xs[i] - mx) * (xs[i] - mx)
            sxy += ws[i] * (xs[i] - mx) * (ys[i] - my)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let slopeVar = 1 / sxx
        let wPrior = 1 / (priorSD * priorSD), wData = 1 / slopeVar
        let pace = (1.0 * wPrior + slope * wData) / (wPrior + wData)
        return Pace(pace: pace, sd: (1 / (wPrior + wData)).squareRoot(), rawSlope: slope,
                    sessions: points.count, windowDays: window)
    }
}
