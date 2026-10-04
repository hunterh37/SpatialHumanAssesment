import ARKit
import QuartzCore
import RealCore
import RealKit
import RealityKit
import ScoreKit
import simd

/// Anatomical overlay on both tracked hands (RealityHD `RealHandAnatomy`): x-ray bones, muscle
/// dissection, or both. Updated every frame from `HandTracker.skeleton`. Without hand tracking
/// (simulator) it shows two demo hands in front of the viewer that slowly open and close.
@MainActor
final class AnatomyOverlay {
    let root = Entity()
    private var hands: [Hand: RealHandAnatomy] = [:]
    private var env: RealEnvironment?
    private var prepared = false
    private(set) var mode: RealHandAnatomy.Mode = .off
    private var demoT: Double = 0
    /// Time of the last ARKit sample applied per hand.
    private var lastSample: [Hand: Double] = [:]
    /// Seconds a hand keeps its last pose after tracking drops before it hides.
    static let holdS = 0.5

    init() {
        RealKitSetup.register()
        RealAtmosphere.fogDensity = 0
        root.name = "anatomy-overlay"
    }

    func prepare() async {
        guard !prepared else { return }
        prepared = true
        async let l = RealHandAnatomy.load(chirality: .left, detail: 0.8)
        async let r = RealHandAnatomy.load(chirality: .right, detail: 0.8)
        let left = await l, right = await r
        hands = [.left: left, .right: right]
        // Neutral studio light so tissue reads the same in the dark stage and in passthrough.
        var sky = SunSky(elevation: 55, azimuth: 160, turbidity: 2.2)
        sky.fogDensity = 0
        sky.sunLux = 3500
        env = try? RealEnvironment(sky, skybox: false)
        if let env {
            root.addChild(env.root)
            env.illuminate(left.root); env.illuminate(right.root)
        }
        root.addChild(left.root); root.addChild(right.root)
        for h in hands.values { await h.prepare() }
        setMode(mode)
    }

    func setMode(_ m: RealHandAnatomy.Mode) {
        mode = m
        lastSample = [:]
        for h in hands.values { h.setMode(m) }
    }

    func update(tracker: HandTracker?, dt: Double) {
        guard mode != .off else { return }
        if let tracker, HandTrackingProvider.isSupported {
            for (side, overlay) in hands {
                // Hold the last pose through short tracking gaps; hiding on every gap made the hands blink.
                guard let sample = tracker.skeletonSample(side, maxAge: Self.holdS) else {
                    if overlay.root.isEnabled {
                        overlay.root.isEnabled = false
                        overlay.resetSmoothing()
                    }
                    lastSample[side] = nil
                    continue
                }
                overlay.root.isEnabled = true
                // Rebuild soft tissue only on a new ARKit sample, not on every render frame.
                guard lastSample[side] != sample.t else { continue }
                lastSample[side] = sample.t
                overlay.update(sample.pose)
            }
            return
        }
        // Simulator: demo hands at chest height, palms down, breathing open and closed.
        demoT += dt
        let curl = Float(0.35 - 0.35 * cos(demoT * 0.8))
        for (side, overlay) in hands {
            let x: Float = side == .left ? -0.13 : 0.13
            let pose = HandPose.rest(side == .left ? .left : .right, origin: SIMD3<Float>(x, 1.15, -0.32),
                                     distal: SIMD3<Float>(x * -0.6, 0.05, -1), dorsal: SIMD3<Float>(0, 1, 0.25), curl: curl)
            overlay.root.isEnabled = true
            overlay.update(pose)
        }
    }
}
