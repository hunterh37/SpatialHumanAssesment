import Observation
import RealityKit
import ScoreKit
import simd

/// One minigame. Plays a block of trials in the immersive stage and returns it for the session.
@MainActor
protocol Minigame {
    static var game: Game { get }
    init(_ ctx: GameContext)
    func play(familiarization: Bool, trials: Int, seed: Int) async -> Block
    /// Removes anything the game left in the scene.
    func teardown()
}

/// Text floating in front of the participant. Never shows a score during play.
@MainActor
@Observable
final class HUD {
    var title = ""
    var line = ""
    var done = 0
    var total = 0
    var visible = false
}

/// Everything a game needs: clock, hands, recorder, scene layer, interaction kit, and a frame at the user.
@MainActor
final class GameContext {
    let clock: FrameClock
    let tracker: HandTracker
    let recorder: SessionRecorder
    let layer: Entity
    let hud: HUD
    let micro: Micro
    let handedness: Participant.Handedness
    private(set) var rig: Rig

    init(clock: FrameClock, tracker: HandTracker, recorder: SessionRecorder, layer: Entity, hud: HUD,
         handedness: Participant.Handedness) {
        self.clock = clock; self.tracker = tracker; self.recorder = recorder; self.layer = layer; self.hud = hud
        self.handedness = handedness
        micro = Micro(clock: clock, root: layer)
        rig = Rig(head: tracker.head())
    }

    var now: Double { recorder.now }

    /// Re-anchor to where the participant now faces. Called at the start of each game.
    func recenter() { rig = Rig(head: tracker.head()) }

    var dominant: Hand { handedness == .left ? .left : .right }

    /// Shoulder of the dominant arm, rig-local.
    var shoulder: SIMD3<Float> { [handedness == .left ? -0.18 : 0.18, rig.eye - 0.25, 0] }

    /// Nearest tracked fingertip to a point.
    func nearestTip(to p: SIMD3<Float>) -> (hand: Hand, tip: SIMD3<Float>, distance: Float)? {
        tracker.trackedHands.map { ($0.0, $0.1.indexTip, simd_distance($0.1.indexTip, p)) }
            .min { $0.2 < $1.2 }
    }

    /// Angle between head forward and the direction to `p`, degrees.
    func eccentricity(of p: SIMD3<Float>) -> Double {
        let head = tracker.head()
        let eye = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let fwd = -SIMD3<Float>(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        let dir = simd_normalize(p - eye)
        return Double(acos(simd_clamp(simd_dot(simd_normalize(fwd), dir), -1, 1))) * 180 / .pi
    }

    /// Point at azimuth/elevation around the shoulder, `reach` meters out, in world space.
    func reachPoint(azimuthDeg: Double, elevationDeg: Double, reach: Float) -> SIMD3<Float> {
        let az = Float(azimuthDeg * .pi / 180), el = Float(elevationDeg * .pi / 180)
        let dir = SIMD3<Float>(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
        return rig.world(shoulder + dir * reach)
    }

    func show(_ game: Game, familiarization: Bool, total: Int) {
        hud.title = game.title
        hud.line = familiarization ? "Practice. \(game.instruction)" : game.instruction
        hud.done = 0
        hud.total = total
        hud.visible = true
    }
}

/// Deterministic per-block randomness. The seed is stored in the block so a run can be replayed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(truncatingIfNeeded: seed) &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
