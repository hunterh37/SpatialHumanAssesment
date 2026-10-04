import ARKit
import QuartzCore
import simd

/// Streams index tip and wrist positions. Spec: specs/architecture.md.
@MainActor
final class HandTracker {
    struct Sample { var t: Double; var indexTip: SIMD3<Float>; var wrist: SIMD3<Float>; var chirality: HandAnchor.Chirality }

    private let session = ARKitSession()
    private let hands = HandTrackingProvider()
    var onSample: ((Sample) -> Void)?

    func run(clockStart: Double) async throws {
        try await session.run([hands])
        for await update in hands.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked, let skeleton = anchor.handSkeleton else { continue }
            let tip = anchor.originFromAnchorTransform * skeleton.joint(.indexFingerTip).anchorFromJointTransform
            let wrist = anchor.originFromAnchorTransform * skeleton.joint(.wrist).anchorFromJointTransform
            onSample?(Sample(t: CACurrentMediaTime() - clockStart,
                             indexTip: tip.columns.3.xyz, wrist: wrist.columns.3.xyz,
                             chirality: anchor.chirality))
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
