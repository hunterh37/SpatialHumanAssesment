import Foundation

/// Reach kinematics from a fingertip trace.
///
/// Pipeline: resample to a uniform 90 Hz grid, Gaussian smooth (sigma 2 samples, about 22 ms),
/// central-difference velocity, then onset, peak, smoothness and path measures.
public struct Kinematics: Sendable {
    public static let rateHz = 90.0
    /// Onset fires when speed stays above this for `sustain` seconds (specs/tasks/simple-reaction.md).
    public static let onsetSpeed = 0.15
    public static let sustain = 0.05
    /// Onset is then walked back to where speed last fell below this fraction of peak speed.
    public static let onsetRefineFraction = 0.05

    public let t: [Double]
    public let p: [V3]
    public let v: [V3]
    public let speed: [Double]

    public init?(_ trace: Trace) {
        guard trace.t.count >= 6, let t0 = trace.t.first, let t1 = trace.t.last, t1 - t0 > 0.1 else { return nil }
        let dt = 1 / Self.rateHz
        let n = Int(((t1 - t0) / dt).rounded(.down)) + 1
        var grid: [Double] = [], pos: [V3] = []
        grid.reserveCapacity(n); pos.reserveCapacity(n)
        var j = 0
        for i in 0..<n {
            let ti = t0 + Double(i) * dt
            while j < trace.t.count - 2 && trace.t[j + 1] < ti { j += 1 }
            let ta = trace.t[j], tb = trace.t[j + 1]
            let w = tb > ta ? min(max((ti - ta) / (tb - ta), 0), 1) : 0
            grid.append(ti)
            pos.append(trace.p[j] * (1 - w) + trace.p[j + 1] * w)
        }
        let smooth = Self.gaussian(pos, sigma: 2)
        var vel = [V3](repeating: .zero, count: n)
        for i in 0..<n {
            let a = max(i - 1, 0), b = min(i + 1, n - 1)
            if b > a { vel[i] = (smooth[b] - smooth[a]) / (grid[b] - grid[a]) }
        }
        t = grid; p = smooth; v = vel; speed = vel.map(\.length)
    }

    static func gaussian(_ xs: [V3], sigma: Double) -> [V3] {
        let r = Int((3 * sigma).rounded(.up))
        let kernel = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        return xs.indices.map { i in
            var acc = V3.zero, wsum = 0.0
            for (k, w) in zip(-r...r, kernel) {
                let idx = i + k
                guard idx >= 0, idx < xs.count else { continue }
                acc = acc + xs[idx] * w; wsum += w
            }
            return acc / wsum
        }
    }

    func index(of time: Double) -> Int {
        guard let first = t.first else { return 0 }
        return min(max(Int(((time - first) * Self.rateHz).rounded()), 0), t.count - 1)
    }

    /// Movement onset after `after` (usually spawn time), or nil if the hand never moved.
    public func onset(after: Double, before: Double? = nil) -> Double? {
        let start = index(of: after)
        let stop = before.map { index(of: $0) } ?? t.count - 1
        guard stop > start else { return nil }
        let need = Int((Self.sustain * Self.rateHz).rounded(.up))
        var run = 0, hit: Int?
        for i in start...stop {
            run = speed[i] > Self.onsetSpeed ? run + 1 : 0
            if run >= need { hit = i - need + 1; break }
        }
        guard let first = hit else { return nil }
        let peakIdx = (first...stop).max(by: { speed[$0] < speed[$1] }) ?? first
        let floor = speed[peakIdx] * Self.onsetRefineFraction
        var i = first
        while i > start && speed[i - 1] > floor { i -= 1 }
        return t[i]
    }

    public struct Reach: Sendable {
        public var peakSpeed: Double
        public var timeToPeak: Double
        public var pathLength: Double
        public var pathEfficiency: Double
        /// Log dimensionless jerk (velocity based). Closer to zero is smoother.
        public var ldlj: Double
        public var submovements: Int
    }

    /// Measures the movement between onset and end (contact).
    public func reach(from start: Double, to end: Double) -> Reach? {
        let a = index(of: start), b = index(of: end)
        guard b - a >= 6 else { return nil }
        let seg = a...b
        let peakIdx = seg.max(by: { speed[$0] < speed[$1] })!
        let peak = speed[peakIdx]
        guard peak > 0 else { return nil }
        var length = 0.0
        for i in (a + 1)...b { length += p[i].distance(to: p[i - 1]) }
        let straight = p[b].distance(to: p[a])

        // Jerk = second derivative of velocity, by finite differences on the uniform grid.
        let dt = 1 / Self.rateHz
        var jerkSq = 0.0
        if b - a >= 3 {
            for i in (a + 1)..<b {
                let j = (v[i + 1] - v[i] * 2 + v[i - 1]) / (dt * dt)
                jerkSq += j.dot(j) * dt
            }
        }
        let duration = t[b] - t[a]
        let dlj = pow(duration, 3) / (peak * peak) * jerkSq
        let ldlj = dlj > 0 ? -log(dlj) : 0

        // Submovements: speed peaks above 20 percent of peak, separated by a 10 percent dip.
        var count = 0, rising = false, lastMin = speed[a]
        for i in (a + 1)...b {
            if speed[i] > speed[i - 1] {
                if !rising && speed[i] - lastMin > 0.1 * peak { rising = true }
            } else if rising && speed[i - 1] > 0.2 * peak {
                count += 1; rising = false; lastMin = speed[i]
            } else {
                lastMin = min(lastMin, speed[i])
            }
        }
        return Reach(peakSpeed: peak, timeToPeak: t[peakIdx] - t[a], pathLength: length,
                     pathEfficiency: length > 0 ? min(straight / length, 1) : 1,
                     ldlj: ldlj, submovements: max(count, 1))
    }
}
