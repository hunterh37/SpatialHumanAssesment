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
    /// Position in the queue, e.g. "2 / 5". Empty for a single game.
    var step = ""
    /// False from the countdown to the end of a block: clouds freeze and the bird keeps to its far ring.
    var ambient = true
    /// Ends the current game only. Set by the Director while a game runs; the HUD shows its skip control.
    var skip: (() -> Void)?
    /// Large center text: countdown digits and short praise. Never a number from play.
    var cue = ""
    /// World positions of the HUD panel and the exit button. Set at each recenter.
    var anchor: SIMD3<Float>?
    var exitAnchor: SIMD3<Float>?
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
    /// Buddy, who explains each game before its blocks. Nil in captures without the stage bird.
    var guide: BirdGuide?
    private(set) var rig: Rig

    init(clock: FrameClock, tracker: HandTracker, recorder: SessionRecorder, layer: Entity, hud: HUD,
         handedness: Participant.Handedness) {
        self.clock = clock; self.tracker = tracker; self.recorder = recorder; self.layer = layer; self.hud = hud
        self.handedness = handedness
        micro = Micro(clock: clock, root: layer)
        rig = Rig(head: tracker.head())
        placeHUD()
    }

    var now: Double { recorder.now }

    /// Re-anchor to where the participant now stands and faces. Called at the start of each game.
    /// Waits for a tracked head first: a frame taken before world tracking runs falls back to the space
    /// origin, which can be meters from the participant, and every game object would be placed around it.
    func recenter() async {
        _ = await tracker.waitForHead()
        rig = Rig(head: tracker.head())
        placeHUD()
    }

    /// HUD at the top of the view, exit button low, both past arm's reach. Spec: Dusk section 7, In play.
    private func placeHUD() {
        let d = Theme.Layout.distance
        hud.anchor = rig.world([0, rig.eye + Theme.Layout.hudRise, -d])
        hud.exitAnchor = rig.world([0, rig.eye - Theme.Layout.exitDrop, -d])
    }

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
        hud.title = game.duskTitle
        hud.line = familiarization ? "Practice. \(game.duskInstruction)" : game.duskInstruction
        if game.isTimed && !familiarization { hud.line += " You are timed." }
        hud.done = 0
        hud.total = total
        hud.cue = ""
        hud.visible = true
    }

    /// Start of a block: a short "Go" cue and chime, no countdown. Play starts immediately.
    func countdown() async {
        // Ambient motion stops here: the bird leaves the hand before the first trial.
        hud.ambient = false
        guard !Task.isCancelled else { return }
        cheer("Go", hold: 0.5)
        Tone.play(.caught, on: layer, gain: -16)
    }

    static let praise = ["Nice.", "Got it.", "Good.", "Well done."]

    /// End of a block: confetti and fanfare 1.1 m ahead at eye height, past arm's reach and above the HUD.
    func celebrateBlock(scored: Bool) {
        micro.juice.finale(at: rig.world([0, rig.eye + 0.05, -1.1]), big: scored)
    }
    private var cueSerial = 0

    /// End of a scored block: the game age reveal, then Buddy flies in and talks about it, then the number
    /// bursts. Returns true when Buddy is still perched for `next` (the next game's explanation follows on).
    func revealAge(_ game: Game, next: Game?) async -> Bool {
        hud.visible = false
        hud.cue = ""
        let result = GameAge.estimate(game, session: recorder.session)
        let reveal = GameAgeReveal(clock: clock, juice: micro.juice, parent: layer)
        defer { if Task.isCancelled { reveal.remove() } }
        await reveal.show(result, rig: rig)
        guard !Task.isCancelled else { return false }
        var stays = false
        if let guide {
            reveal.lift(rig)
            let lines = result?.lines(next: next)
                ?? ["Done! Not enough clean moves to score that one."] + (next.map { ["Next up: \($0.duskTitle). Ready?"] } ?? [])
            await guide.say(lines, action: next == nil ? "See my results" : "Next game", rig: rig, stay: next != nil)
            stays = next != nil
        } else {
            await clock.wait(2.6)
        }
        guard !Task.isCancelled else { return false }
        await reveal.dissolve()
        return stays && !Task.isCancelled
    }

    /// Short praise on the HUD for `hold` seconds. A newer cue replaces it.
    func cheer(_ text: String? = nil, hold: Double = 0.8) {
        cueSerial += 1
        let serial = cueSerial
        hud.cue = text ?? micro.juice.takeWord() ?? Self.praise.randomElement()!
        Task { @MainActor in
            await clock.wait(hold)
            if cueSerial == serial { hud.cue = "" }
        }
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
