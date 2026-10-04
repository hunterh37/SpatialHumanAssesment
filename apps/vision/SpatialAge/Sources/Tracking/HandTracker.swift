import ARKit
import QuartzCore
import ScoreKit
import simd

/// Streams hand joints and head pose into one session clock. Spec: specs/architecture.md.
///
/// Every tracked hand update is written to `TraceBuffer`, so any trial can later pull the exact
/// fingertip path and tracking gaps for its time window.
@MainActor
final class HandTracker {
    struct HandState {
        var t: Double
        var indexTip: SIMD3<Float>
        var thumbTip: SIMD3<Float>
        var wrist: SIMD3<Float>
        /// Midpoint of thumb and index tips. The point that closes on an object in a pinch grasp.
        var grasp: SIMD3<Float> { (indexTip + thumbTip) / 2 }
        var aperture: Float { simd_distance(indexTip, thumbTip) }
    }

    private let session = ARKitSession()
    private let hands = HandTrackingProvider()
    private let world = WorldTrackingProvider()
    private let clockStart: Double

    private(set) var left: HandState?
    private(set) var right: HandState?
    let buffer = TraceBuffer()

    /// Samples older than this are treated as not tracked.
    static let staleS = 0.1

    init(clockStart: Double) { self.clockStart = clockStart }

    var now: Double { CACurrentMediaTime() - clockStart }

    func state(_ hand: Hand) -> HandState? {
        guard let s = hand == .left ? left : right, now - s.t < Self.staleS else { return nil }
        return s
    }

    var trackedHands: [(Hand, HandState)] {
        [Hand.left, .right].compactMap { h in state(h).map { (h, $0) } }
    }

    /// Head pose in world space. Identity at 1.5 m when world tracking is unavailable (simulator).
    func head() -> simd_float4x4 {
        if let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), anchor.isTracked {
            return anchor.originFromAnchorTransform
        }
        var m = matrix_identity_float4x4
        m.columns.3 = [0, 1.5, 0, 1]
        return m
    }

    func run() async {
        guard HandTrackingProvider.isSupported else { return }
        do { try await session.run([hands, world]) } catch { return }
        for await update in hands.anchorUpdates {
            let anchor = update.anchor
            let t = now
            let hand: Hand = anchor.chirality == .left ? .left : .right
            guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
                buffer.lost(hand, at: t)
                continue
            }
            func joint(_ name: HandSkeleton.JointName) -> SIMD3<Float> {
                let m = anchor.originFromAnchorTransform * skeleton.joint(name).anchorFromJointTransform
                return SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            }
            let s = HandState(t: t, indexTip: joint(.indexFingerTip), thumbTip: joint(.thumbTip), wrist: joint(.wrist))
            if hand == .left { left = s } else { right = s }
            buffer.append(hand, s)
        }
    }
}

/// Session-long record of hand samples, per hand, for trace and gap queries.
@MainActor
final class TraceBuffer {
    private var samples: [Hand: [HandTracker.HandState]] = [.left: [], .right: []]
    private var losses: [Hand: [Double]] = [.left: [], .right: []]

    func append(_ hand: Hand, _ s: HandTracker.HandState) { samples[hand, default: []].append(s) }
    func lost(_ hand: Hand, at t: Double) { losses[hand, default: []].append(t) }

    func window(_ hand: Hand, _ from: Double, _ to: Double) -> [HandTracker.HandState] {
        guard let all = samples[hand] else { return [] }
        // Binary search for the window start; the buffer is time ordered.
        var lo = 0, hi = all.count
        while lo < hi { let mid = (lo + hi) / 2; if all[mid].t < from { lo = mid + 1 } else { hi = mid } }
        var out: [HandTracker.HandState] = []
        var i = lo
        while i < all.count && all[i].t <= to { out.append(all[i]); i += 1 }
        return out
    }

    /// Fingertip path for the schema `trace` field.
    func trace(_ hand: Hand, _ from: Double, _ to: Double) -> Trace {
        var tr = Trace()
        for s in window(hand, from, to) {
            tr.append(s.t, V3(Double(s.indexTip.x), Double(s.indexTip.y), Double(s.indexTip.z)))
        }
        return tr
    }

    /// Longest interval without a tracked sample, ms. Uses either hand when `hand` is nil.
    func maxGapMs(_ hand: Hand?, _ from: Double, _ to: Double) -> Double {
        let hands = hand.map { [$0] } ?? [.left, .right]
        var best = Double.infinity
        for h in hands {
            let ts = [from] + window(h, from, to).map(\.t) + [to]
            let gap = zip(ts.dropFirst(), ts).map { $0 - $1 }.max() ?? (to - from)
            best = min(best, gap)
        }
        return best.isFinite ? best * 1000 : (to - from) * 1000
    }
}

extension SIMD3 where Scalar == Float {
    var v3: V3 { V3(Double(x), Double(y), Double(z)) }
}
