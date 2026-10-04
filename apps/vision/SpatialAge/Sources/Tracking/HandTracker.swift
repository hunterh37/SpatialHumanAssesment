import ARKit
import QuartzCore
import struct RealCore.HandPose
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
        /// All skeleton joints in world space, `jointOrder`. Used for whole-hand contact.
        var joints: [SIMD3<Float>] = []
        /// Midpoint of thumb and index tips. The point that closes on an object in a pinch grasp.
        var grasp: SIMD3<Float> { (indexTip + thumbTip) / 2 }
        var aperture: Float { simd_distance(indexTip, thumbTip) }
        /// Distance from `p` to the nearest joint or bone segment (wrist to tips). Falls back to tips and wrist.
        func contactDistance(to p: SIMD3<Float>) -> Float {
            guard joints.count >= 25 else {
                return [indexTip, thumbTip, wrist, grasp].map { simd_distance($0, p) }.min()!
            }
            // Chains per jointOrder: thumb 1-4, fingers 5-9, 10-14, 15-19, 20-24, each from the wrist (0).
            let chains = [Array(1...4), Array(5...9), Array(10...14), Array(15...19), Array(20...24)]
            var best = simd_distance(joints[0], p)
            for chain in chains {
                var a = joints[0]
                for i in chain {
                    let b = joints[i]
                    let ab = b - a
                    let len2 = simd_length_squared(ab)
                    let k = len2 > 0 ? simd_clamp(simd_dot(p - a, ab) / len2, 0, 1) : 0
                    best = min(best, simd_distance(a + k * ab, p))
                    a = b
                }
            }
            // Palm: knuckle-to-knuckle span between index and little.
            for (i, j) in [(6, 11), (11, 16), (16, 21)] {
                let a = joints[i], ab = joints[j] - a
                let len2 = simd_length_squared(ab)
                let k = len2 > 0 ? simd_clamp(simd_dot(p - a, ab) / len2, 0, 1) : 0
                best = min(best, simd_distance(a + k * ab, p))
            }
            return best
        }
    }

    private let session = ARKitSession()
    private let hands = HandTrackingProvider()
    private let world = WorldTrackingProvider()
    private let clockStart: Double

    private(set) var left: HandState?
    private(set) var right: HandState?
    /// All 27 joints per hand in world space, for the anatomy overlay.
    private(set) var skeletons: [Hand: (t: Double, pose: HandPose)] = [:]
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
        if let m = trackedHead() { return m }
        var m = matrix_identity_float4x4
        m.columns.3 = [0, 1.5, 0, 1]
        return m
    }

    /// Head pose in world space, nil until world tracking reports a tracked device anchor.
    func trackedHead() -> simd_float4x4? {
        guard world.state == .running,
              let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), anchor.isTracked else { return nil }
        return anchor.originFromAnchorTransform
    }

    /// Waits up to `timeout` seconds for a tracked head. False when it never came (simulator, tracking lost).
    func waitForHead(timeout: Double = 3) async -> Bool {
        let end = CACurrentMediaTime() + timeout
        while trackedHead() == nil {
            guard CACurrentMediaTime() < end, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// Full skeleton of a hand, nil when stale or untracked.
    func skeleton(_ hand: Hand) -> HandPose? {
        skeletonSample(hand)?.pose
    }

    /// Latest skeleton with its sample time, nil when older than `maxAge` seconds.
    func skeletonSample(_ hand: Hand, maxAge: Double = staleS) -> (t: Double, pose: HandPose)? {
        guard let s = skeletons[hand], now - s.t < maxAge else { return nil }
        return s
    }

    static let jointOrder: [HandSkeleton.JointName] = [
        .wrist,
        .thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip,
        .indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip,
        .middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip,
        .ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip,
        .littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip,
        .forearmWrist, .forearmArm,
    ]

    /// Stops ARKit hand and world tracking. Ends `run()`.
    func stop() { session.stop() }

    func run() async {
        guard HandTrackingProvider.isSupported else { return }
        do { try await session.run([hands, world]) } catch { return }
        for await update in hands.anchorUpdates {
            if Task.isCancelled { break }
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
            let joints = Self.jointOrder.map(joint)
            let s = HandState(t: t, indexTip: joint(.indexFingerTip), thumbTip: joint(.thumbTip), wrist: joint(.wrist),
                              joints: joints)
            skeletons[hand] = (t, HandPose(chirality: hand == .left ? .left : .right, positions: joints))
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
