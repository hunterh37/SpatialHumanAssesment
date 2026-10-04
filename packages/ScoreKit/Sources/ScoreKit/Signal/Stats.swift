import Foundation

/// Robust and distributional statistics used by the metric extractors.
public enum Stats {
    public static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    public static func sd(_ xs: [Double]) -> Double? {
        guard xs.count > 1, let m = mean(xs) else { return nil }
        return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot()
    }

    public static func quantile(_ xs: [Double], _ q: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let pos = q * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    public static func median(_ xs: [Double]) -> Double? { quantile(xs, 0.5) }

    /// Median absolute deviation scaled to match SD under normality.
    public static func mad(_ xs: [Double]) -> Double? {
        guard let m = median(xs) else { return nil }
        return median(xs.map { abs($0 - m) }).map { $0 * 1.4826 }
    }

    /// Drops values more than `k` scaled MADs from the median. Keeps all when MAD is zero.
    public static func trimOutliers(_ xs: [Double], k: Double = 3) -> [Double] {
        guard xs.count >= 5, let m = median(xs), let d = mad(xs), d > 0 else { return xs }
        return xs.filter { abs($0 - m) <= k * d }
    }

    /// Standard error of the median, asymptotic normal approximation.
    public static func semMedian(_ xs: [Double]) -> Double? {
        guard xs.count > 2, let s = sd(xs) else { return nil }
        return 1.2533 * s / Double(xs.count).squareRoot()
    }

    public static func skewness(_ xs: [Double]) -> Double? {
        guard xs.count > 2, let m = mean(xs), let s = sd(xs), s > 0 else { return nil }
        let n = Double(xs.count)
        let m3 = xs.reduce(0) { $0 + pow($1 - m, 3) } / n
        return m3 / pow(s, 3)
    }

    /// Ex-Gaussian parameters by method of moments (Heathcote 1996, Lacouture and Cousineau 2008).
    /// `tau` is the exponential tail, the part of RT variability that grows most with age.
    public struct ExGaussian: Sendable { public var mu, sigma, tau: Double }

    public static func exGaussian(_ xs: [Double]) -> ExGaussian? {
        guard xs.count >= 8, let m = mean(xs), let s = sd(xs), let g0 = skewness(xs) else { return nil }
        let g = min(max(g0, 0.01), 1.99)
        let r = pow(g / 2, 1.0 / 3.0)
        let tau = s * r
        let sigma = s * max(0, 1 - r * r).squareRoot()
        return ExGaussian(mu: m - tau, sigma: sigma, tau: tau)
    }

    public struct Line: Sendable { public var slope, intercept, slopeSE: Double }

    /// Ordinary least squares with the standard error of the slope.
    public static func ols(_ xs: [Double], _ ys: [Double]) -> Line? {
        guard xs.count == ys.count, xs.count >= 3, let mx = mean(xs), let my = mean(ys) else { return nil }
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let sse = zip(xs, ys).reduce(0) { $0 + pow($1.1 - (intercept + slope * $1.0), 2) }
        let se = (sse / Double(xs.count - 2) / sxx).squareRoot()
        return Line(slope: slope, intercept: intercept, slopeSE: se)
    }

    /// Theil-Sen slope: median of pairwise slopes. Robust to a single bad session.
    public static func theilSen(_ xs: [Double], _ ys: [Double]) -> Double? {
        var slopes: [Double] = []
        for i in 0..<xs.count { for j in (i + 1)..<xs.count where xs[j] != xs[i] {
            slopes.append((ys[j] - ys[i]) / (xs[j] - xs[i]))
        } }
        return median(slopes)
    }

    public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count > 2, let mx = mean(xs), let my = mean(ys) else { return nil }
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let dx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }.squareRoot()
        let dy = ys.reduce(0) { $0 + ($1 - my) * ($1 - my) }.squareRoot()
        return dx > 0 && dy > 0 ? num / (dx * dy) : nil
    }

    /// Standard normal CDF.
    public static func phi(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }

    /// Inverse standard normal CDF (Acklam's rational approximation, |error| < 1.2e-9).
    public static func phiInverse(_ p: Double) -> Double {
        let p = min(max(p, 1e-9), 1 - 1e-9)
        let a = [-39.69683028665376, 220.9460984245205, -275.9285104469687, 138.3577518672690, -30.66479806614716, 2.506628277459239]
        let b = [-54.47609879822406, 161.5858368580409, -155.6989798598866, 66.80131188771972, -13.28068155288572]
        let c = [-0.007784894002430293, -0.3223964580411365, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783]
        let d = [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416]
        let pl = 0.02425
        if p < pl {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        }
        if p > 1 - pl {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        }
        let q = p - 0.5, r = q * q
        return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q / (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)
    }

    /// Signal detection sensitivity with the log-linear correction (Hautus 1995).
    public static func dPrime(hits: Int, goTrials: Int, falseAlarms: Int, nogoTrials: Int) -> Double? {
        guard goTrials > 0, nogoTrials > 0 else { return nil }
        let h = (Double(hits) + 0.5) / (Double(goTrials) + 1)
        let f = (Double(falseAlarms) + 0.5) / (Double(nogoTrials) + 1)
        return phiInverse(h) - phiInverse(f)
    }
}
