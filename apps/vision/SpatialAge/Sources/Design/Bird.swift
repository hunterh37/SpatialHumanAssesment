import RealityKit
import simd
import ScoreKit
import UIKit

/// Yellow songbird (canary build, life size) living in the Dusk stage. Spec: specs/games/design.md, Bird.
///
/// It always flies in front of the participant: waypoints stay inside an arc around where the head faces
/// (smoothed), and when the participant turns away it flies around the near side back into view, never
/// across or behind them.
///
/// Between blocks it flies bounding loops 2.6 to 4.8 m out and answers an offered hand: a hand held out,
/// open, palm up and still for 0.3 s calls it in. It lands on the palm, faces the participant, blinks,
/// tilts its head, hops, flicks its tail and chirps. A finger from the other hand near its head pets it.
/// Turning the palm over, lowering or closing the hand sends it off; a fast shake startles it off.
/// When a countdown starts (`ambient` false) it leaves the hand, stays silent and keeps to a far ring
/// 13 to 17 m out and 6 to 8.5 m up, so nothing near the targets moves during trials.
/// As the game guide (`BirdGuide`) it flies in, lands on a small floating twig and talks.
@MainActor
final class Bird {
    /// Static container in the stage. Holds the flying bird and the guide twig.
    let root = Entity()
    /// The bird itself; moves every frame. Sounds play from here.
    let flight = Entity()
    /// Floating perch for scripted landings (intro, game guide). Grows in on `summon`, shrinks after takeoff.
    private let twig = Entity()
    private var twigGrow: Float = 0, twigVel: Float = 0

    // Rig. Bird space: origin between the feet, -Z forward, +Y up.
    private let poseNode = Entity()
    private let body = Entity()
    private let head = Entity()
    private var eyes: [Entity] = []
    private let lowerBeak = Entity()
    private var wings: [Wing] = []
    private let tail = Entity()
    private var tailFeathers: [Entity] = []
    private let legs = Entity()

    private struct Wing {
        let side: Float
        let shoulder: Entity
        let hand: Entity
        /// Feather entity and its spread-pose fan angle around the local Y axis.
        var feathers: [(Entity, Float)]
    }

    // Placement of the rig parts, bird space.
    private static let headPivot = SIMD3<Float>(0, 0.076, -0.027)
    private static let headCenter = SIMD3<Float>(0, 0.006, -0.004)

    // Flight state, world space.
    private enum Mode { case wander, approach, land, perch, takeoff }
    private var mode = Mode.wander
    private var p = SIMD3<Float>(0, 2.4, -4)
    private var v = SIMD3<Float>(1.2, 0, 0)
    private var yaw: Float = 0, pitch: Float = 0, bank: Float = 0
    private var center = SIMD3<Float>(0, 0, 0)
    private var waypoint = SIMD3<Float>(3, 2.2, -3)
    private var orbit: Float = 0
    private var orbitDir: Float = 1
    private var far = false
    private var rng = SeededRNG(seed: 0xB1D)
    /// Smoothed horizontal facing of the participant, Rig yaw convention. Nil until the first frame.
    private var facing: Float?
    /// Half-width of the flight arc in front of the participant, radians.
    static let nearArc: Float = 0.95
    static let farArc: Float = 0.7

    // Wing and body pose.
    private var flapPhase: Float = 0
    private var bound: Float = 0
    private var flapWeight: Float = 0
    private var flap: Float = -0.55
    private var fold: Float = 1
    private var handCurl: Float = 0
    private var tailSpread: Float = 0.1
    private var tailLift: Float = 0
    private var legsOut: Float = 1
    private var perchTilt: Float = 0
    private var lastWingPose = SIMD3<Float>(repeating: .nan)

    // Hand perch.
    private var hand: Hand?
    private var perchPoint = SIMD3<Float>.zero
    private var offerTime: Float = 0
    private var lostTime: Float = 0
    private var cooldown: Float = 0
    private var landFrom = SIMD3<Float>.zero
    private var landT: Float = 0
    private var takeoffT: Float = 0
    private var palmPrev: [Hand: SIMD3<Float>] = [:]
    private var palmSpeed: [Hand: Float] = [:]

    // Idle life.
    private var clock: Float = 0
    private var blinkIn: Float = 2, blinkT: Float = -1
    private var lookAt: SIMD3<Float>?
    private var lookIn: Float = 0
    private var headYaw: Float = 0, headPitch: Float = 0, headRoll: Float = 0, rollGoal: Float = 0
    private var hopIn: Float = 5, hopT: Float = -1, hopTurn: Float = 0
    private var flickIn: Float = 2, flickT: Float = -1
    private var chirpIn: Float = 3, beakT: Float = -1
    private var puff: Float = 0, happy: Float = 0, balance: Float = 0
    private var petCooldown: Float = 0

    static let landSeconds: Float = 0.32
    static let offerHold: Float = 0.3
    static let loseHold: Float = 0.3
    /// Palm speed that startles the bird off the hand, m/s.
    static let startle: Float = 1.7

    init() {
        root.name = "bird"
        flight.name = "bird-body"
        root.addChild(flight)
        flight.addChild(poseNode)
        build()
        flight.position = p
        twig.name = "bird-twig"
        twig.isEnabled = false
        root.addChild(twig)
        buildTwig()
    }

    // MARK: Per frame

    /// Call every frame. `ambient` false (countdown and trials): no landing, no song, far ring only.
    func update(dt rawDt: Double, tracker: HandTracker?, ambient: Bool) {
        let dt = Float(min(max(rawDt, 0), 1.0 / 30))
        guard dt > 0 else { return }
        clock += dt
        cooldown = max(0, cooldown - dt)
        petCooldown = max(0, petCooldown - dt)

        let headM = tracker?.head() ?? {
            var m = matrix_identity_float4x4
            m.columns.3 = [0, 1.5, 0, 1]
            return m
        }()
        let eye = SIMD3<Float>(headM.columns.3.x, headM.columns.3.y, headM.columns.3.z)
        center += (SIMD3<Float>(eye.x, 0, eye.z) - center) * min(1, dt * 0.5)
        let headYaw = Rig(head: headM).yaw
        if let f = facing {
            facing = wrap(f + wrap(headYaw - f) * min(1, dt * 1.5))
        } else {
            facing = headYaw
            center = SIMD3<Float>(eye.x, 0, eye.z)
            pickWaypoint(fresh: true)
        }
        lastEye = eye

        if far == ambient {
            far = !ambient
            pickWaypoint(fresh: true)
        }

        var offers: [Hand: Offer] = [:]
        if let tracker {
            for (h, s) in tracker.trackedHands { offers[h] = offer(h, s, eye: eye, dt: dt) }
        }

        switch mode {
        case .wander: wander(offers, eye: eye, ambient: ambient, dt: dt)
        case .approach: approach(offers, eye: eye, ambient: ambient, dt: dt)
        case .land: land(offers, eye: eye, ambient: ambient, dt: dt)
        case .perch: perch(offers, tracker: tracker, eye: eye, ambient: ambient, dt: dt)
        case .takeoff:
            takeoffT += dt
            v.y -= 1.2 * dt
            p += v * dt
            if takeoffT > 0.7 { mode = .wander; pickWaypoint(fresh: true) }
        }

        if ambient, mode == .wander || mode == .approach {
            chirpIn -= dt
            if chirpIn <= 0 {
                chirp(.chirp(1), gain: -26)
                chirpIn = .random(in: 5...10, using: &rng)
            }
        }

        orient(eye: eye, dt: dt)
        animate(eye: eye, dt: dt)
        growTwig(dt: dt)
    }

    // MARK: Modes

    private func wander(_ offers: [Hand: Offer], eye: SIMD3<Float>, ambient: Bool, dt: Float) {
        var speed: Float = UIAccessibility.isReduceMotionEnabled ? 1.4 : (far ? 4.0 : 2.6)
        // Back from the far ring: hurry in.
        if !far, simd_length(SIMD2<Float>(p.x - center.x, p.z - center.z)) > 7 { speed = max(speed, 4.5) }
        if let around = herd() {
            waypoint = around
            speed *= 1.6
        }
        steer(to: waypoint, speed: speed, rate: 2.2, dt: dt)
        if simd_distance(p, waypoint) < (far ? 1.6 : 0.8) { pickWaypoint(fresh: false) }

        guard ambient, cooldown == 0, let best = nearestOffer(offers) else { offerTime = 0; return }
        offerTime += dt
        if offerTime >= Self.offerHold {
            hand = best.hand
            perchPoint = best.perch
            mode = .approach
            lostTime = 0
            chirp(.chirp(0), gain: -20)
            chirpIn = .random(in: 4...7, using: &rng)
        }
    }

    private func approach(_ offers: [Hand: Offer], eye: SIMD3<Float>, ambient: Bool, dt: Float) {
        guard ambient else { flyAway(eye: eye, startled: false); return }
        if !track(offers, dt: dt) { flyAway(eye: eye, startled: false); return }
        // Come in from the far side of the hand, a little high, so the bird never crosses the face.
        var out = perchPoint - eye
        out.y = 0
        out = simd_length(out) > 1e-3 ? simd_normalize(out) : [0, 0, -1]
        let staging = perchPoint + out * 0.7 + [0, 0.3, 0]
        let d = simd_distance(p, perchPoint)
        var target = d > 0.9 && simd_distance(p, staging) > 0.35 ? staging : perchPoint + [0, 0.03, 0]
        // Behind or beside the participant: come around the near side first.
        if d > 0.9, let around = herd() { target = around }
        // Long legs (called back from the far ring) fly fast; the last meter slows into the flare.
        let speed = simd_clamp(simd_distance(p, target) * 1.8, 0.45, d > 4 ? 7 : 2.6)
        steer(to: target, speed: speed, rate: d > 4 ? 3 : 4, dt: dt)
        if d < 0.28 {
            mode = .land
            landFrom = p
            landT = 0
        }
    }

    private func land(_ offers: [Hand: Offer], eye: SIMD3<Float>, ambient: Bool, dt: Float) {
        guard ambient, track(offers, dt: dt) else { flyAway(eye: eye, startled: false); return }
        landT += dt
        let k = Float(Ease.out(Double(min(landT / Self.landSeconds, 1))))
        let next = landFrom + (perchPoint - landFrom) * k
        v = (next - p) / dt
        p = next
        if landT >= Self.landSeconds {
            mode = .perch
            v = .zero
            puff = 1
            hopIn = .random(in: 3...6, using: &rng)
            chirpIn = .random(in: 0.6...1.4, using: &rng)
            lookAt = eye
            lookIn = 1.2
        }
    }

    private func perch(_ offers: [Hand: Offer], tracker: HandTracker?, eye: SIMD3<Float>, ambient: Bool, dt: Float) {
        guard ambient else { flyAway(eye: eye, startled: false); return }
        guard track(offers, dt: dt) else { flyAway(eye: eye, startled: false); return }
        let speed = hand.flatMap { palmSpeed[$0] } ?? 0
        if speed > Self.startle { flyAway(eye: eye, startled: true); return }
        balance = max(balance, simd_clamp((speed - 0.35) / 0.8, 0, 1))
        p += (perchPoint - p) * (1 - exp(-30 * dt))
        v = .zero

        // Petting: a fingertip of the other hand near the head or back.
        if let tracker, let mine = hand {
            let headW = poseNode.convert(position: Self.headPivot + Self.headCenter, to: nil)
            let backW = poseNode.convert(position: [0, 0.06, 0.01], to: nil)
            for (h, s) in tracker.trackedHands where h != mine {
                let tip = s.indexTip
                let near = min(simd_distance(tip, headW), simd_distance(tip, backW))
                guard near < 0.05 else { continue }
                let tipSpeed = palmSpeed[h] ?? 0
                if tipSpeed > 0.9 {
                    if petCooldown == 0 { startHop(turn: 0.5); balance = 1; chirp(.alarm, gain: -22); petCooldown = 1.2 }
                } else {
                    happy = min(1, happy + dt * 4)
                    puff = max(puff, 0.6)
                    rollGoal = (tip.x - headW.x) > 0 ? -0.35 : 0.35
                    if petCooldown == 0 { chirp(.trill, gain: -20); petCooldown = 2.2 }
                }
            }
        }

        // Idle behaviors.
        chirpIn -= dt
        if chirpIn <= 0 {
            chirp(.chirp(Int.random(in: 0...3, using: &rng)), gain: -20)
            chirpIn = .random(in: 2.5...6, using: &rng)
        }
        hopIn -= attentive ? dt * 0.3 : dt
        if hopIn <= 0, balance < 0.2 {
            startHop(turn: .random(in: -0.6...0.6, using: &rng))
            hopIn = .random(in: 4...8, using: &rng)
        }
        flickIn -= dt
        if flickIn <= 0 {
            flickT = 0
            flickIn = .random(in: 1.4...3.2, using: &rng)
        }
    }

    /// Scripted perch point (intro sequence, captures). While set, the bird treats it as an offered hand.
    private var pinned: SIMD3<Float>?

    /// Intro sequence and game guide: a twig grows at `point`, the bird flies in from where it is, lands
    /// on it and perches there facing the participant.
    func summon(to point: SIMD3<Float>) {
        let moved = pinned.map { simd_distance($0, point) > 0.05 } ?? true
        if moved {
            twig.position = point
            // Twig local -Z toward the participant, so the branch runs across their view.
            var d = lastEye - point
            d.y = 0
            if simd_length(d) > 1e-3 { twig.orientation = simd_quatf(angle: atan2(-d.x, -d.z), axis: [0, 1, 0]) }
        }
        pinned = point
        perchPoint = point
        hand = nil
        lostTime = 0
        cooldown = 0
        if mode == .perch || mode == .land { return }
        mode = .approach
        chirp(.chirp(0), gain: -18)
    }

    /// Ends a scripted perch: the bird takes off and goes back to wandering; the twig shrinks away.
    func dismiss() {
        guard pinned != nil else { return }
        pinned = nil
        attentive = false
    }

    /// True once the bird sits on its scripted perch.
    var perched: Bool { mode == .perch && pinned != nil }

    /// Guide mode: while true the perched bird mostly looks at the participant and does not hop about.
    var attentive = false

    /// One spoken word of a speech bubble: a soft syllable, the bill opens, the head bobs.
    func talk(_ word: Int) {
        guard mode == .perch, !far else { return }
        Tone.play(.peep(word &* 7 &+ Int(clock * 10)), on: flight, gain: -27)
        beakT = 0
        puff = max(puff, 0.15)
        if word % 3 == 0 { rollGoal = .random(in: -0.25...0.25, using: &rng) }
        lookAt = lastEye
        lookIn = max(lookIn, 0.6)
    }

    /// Plays one call from the bird (intro lines).
    func sing() {
        chirp(.trill, gain: -18)
        startHop(turn: 0)
    }

    #if DEBUG
    /// Captures: perches the bird at a fixed point as if on a hand, until the space closes.
    func preview(at point: SIMD3<Float>) {
        pinned = point
        perchPoint = point
        p = point
        mode = .perch
        legsOut = 1
        flapWeight = 0
    }
    #endif

    /// Updates the perch point from the tracked hand. False once the offer has been gone for `loseHold`.
    private func track(_ offers: [Hand: Offer], dt: Float) -> Bool {
        if let pinned { perchPoint = pinned; return true }
        guard let h = hand else { return false }
        if let o = offers[h] {
            perchPoint = o.perch
            if o.ok { lostTime = 0; return true }
        }
        lostTime += dt
        return lostTime < Self.loseHold
    }

    private var lastEye = SIMD3<Float>(0, 1.5, 0)

    private func flyAway(eye: SIMD3<Float>, startled: Bool) {
        let wasNear = mode == .perch || mode == .land
        var out = p - eye
        out.y = 0
        out = simd_length(out) > 1e-3 ? simd_normalize(out) : [0, 0, -1]
        let side = simd_cross([0, 1, 0], out) * Float.random(in: -0.6...0.6, using: &rng)
        v = (out + side) * (startled ? 2.6 : 1.7) + [0, startled ? 2.2 : 1.5, 0]
        if !wasNear { v = simd_length(v) > 0 ? v : [0, 1, 0] }
        mode = .takeoff
        takeoffT = 0
        hand = nil
        offerTime = 0
        lostTime = 0
        cooldown = startled ? 2.0 : 1.0
        happy = 0
        if wasNear {
            Tone.play(.whirr, on: flight, gain: -24)
            if startled && !far { chirp(.alarm, gain: -20) }
        }
        orbit = atan2(p.x - center.x, -(p.z - center.z))
        pickWaypoint(fresh: true)
    }

    private func startHop(turn: Float) {
        hopT = 0
        hopTurn += turn
        hopTurn = simd_clamp(hopTurn, -0.9, 0.9)
        flickT = 0
    }

    private func chirp(_ cue: Tone.Cue, gain: Double) {
        guard !far else { return }
        Tone.play(cue, on: flight, gain: gain)
        beakT = 0
        puff = max(puff, 0.3)
    }

    // MARK: Hand offer

    private struct Offer {
        let hand: Hand
        let perch: SIMD3<Float>
        let ok: Bool
    }

    /// Palm up, open, held out in front, steady.
    private func offer(_ h: Hand, _ s: HandTracker.HandState, eye: SIMD3<Float>, dt: Float) -> Offer {
        let j = s.joints
        guard j.count >= 25 else { return Offer(hand: h, perch: s.wrist, ok: false) }
        let knuckles = (j[6] + j[11] + j[16] + j[21]) / 4
        let palm = knuckles * 0.55 + j[0] * 0.45
        var n = simd_cross(j[6] - j[0], j[21] - j[0])
        if h == .left { n = -n }
        n = simd_length(n) > 1e-6 ? simd_normalize(n) : [0, -1, 0]

        let prev = palmPrev[h] ?? palm
        let instant = simd_distance(palm, prev) / dt
        palmPrev[h] = palm
        let speed = (palmSpeed[h] ?? 0) + (instant - (palmSpeed[h] ?? 0)) * min(1, dt * 12)
        palmSpeed[h] = speed

        var reach = palm - eye
        reach.y = 0
        let open = simd_distance(j[14], j[0]) > 0.12
        let up = n.y > 0.55
        let out = simd_length(reach) > 0.28
        let raised = palm.y > eye.y - 0.75
        let still = mode == .perch || mode == .land ? true : speed < 0.4
        let perch = palm + n * 0.008 + [0, 0.004, 0]
        return Offer(hand: h, perch: perch, ok: open && up && out && raised && still)
    }

    private func nearestOffer(_ offers: [Hand: Offer]) -> Offer? {
        offers.values.filter(\.ok).min { simd_distance($0.perch, p) < simd_distance($1.perch, p) }
    }

    // MARK: Flight

    private func steer(to target: SIMD3<Float>, speed: Float, rate: Float, dt: Float) {
        let d = target - p
        let dist = simd_length(d)
        let desired = dist > 1e-4 ? d / dist * speed : .zero
        v += (desired - v) * min(1, rate * dt)
        p += v * dt
    }

    /// Orbit angle (0 = -Z, positive toward +X) straight ahead of the participant.
    private var ahead: Float { -(facing ?? 0) }

    /// Next loop waypoint, inside the arc in front of the participant. At an arc edge the bird turns back.
    private func pickWaypoint(fresh: Bool) {
        if fresh {
            orbit = atan2(p.x - center.x, -(p.z - center.z))
        }
        let arc = far ? Self.farArc : Self.nearArc
        let rel = simd_clamp(wrap(orbit - ahead), -arc, arc)
        if Float.random(in: 0...1, using: &rng) < 0.12 { orbitDir = -orbitDir }
        let step = Float.random(in: 0.4...0.85, using: &rng)
        var next = rel + step * orbitDir
        if abs(next) > arc {
            orbitDir = -orbitDir
            next = simd_clamp(rel + step * orbitDir, -arc, arc)
        }
        orbit = ahead + next
        let r = far ? Float.random(in: 13...17, using: &rng) : .random(in: 2.6...4.8, using: &rng)
        let h = far ? Float.random(in: 6...8.5, using: &rng) : .random(in: 1.7...3.1, using: &rng)
        waypoint = center + [sin(orbit) * r, h, -cos(orbit) * r]
    }

    /// When the bird has drifted out of the front arc (the participant turned), a waypoint up to 57 degrees
    /// further around the circle on the side the bird is already on, so it sweeps back into view around
    /// the participant instead of cutting across or behind them. Nil while it is in view.
    private func herd() -> SIMD3<Float>? {
        let off = SIMD2<Float>(p.x - center.x, p.z - center.z)
        let rel = wrap(atan2(off.x, -off.y) - ahead)
        let arc = far ? Self.farArc : Self.nearArc
        guard abs(rel) > arc + 0.2 else { return nil }
        let side: Float = rel >= 0 ? 1 : -1
        let a = ahead + rel - side * min(abs(rel) - arc * 0.5, 1.0)
        let r = max(simd_length(off), far ? 13 : 2.6)
        orbit = a
        orbitDir = -side
        let h = max(p.y, far ? 6 : 1.7)
        return center + [sin(a) * r, h, -cos(a) * r]
    }

    private func orient(eye: SIMD3<Float>, dt: Float) {
        var yawGoal = yaw, pitchGoal: Float = 0, bankGoal: Float = 0
        switch mode {
        case .perch:
            yawGoal = atan2(-(eye.x - p.x), -(eye.z - p.z)) + hopTurn
        case .land:
            var d = perchPoint - landFrom
            d.y = 0
            if simd_length(d) > 1e-3 { yawGoal = atan2(-d.x, -d.z) }
            pitchGoal = 0.55
        default:
            let hs = simd_length(SIMD2<Float>(v.x, v.z))
            if hs > 0.08 { yawGoal = atan2(-v.x, -v.z) }
            pitchGoal = simd_clamp(atan2(v.y, max(hs, 0.1)), -0.5, 0.6)
        }
        let dy = wrap(yawGoal - yaw)
        let turn = dy * min(1, (mode == .perch ? 6 : 7) * dt)
        yaw = wrap(yaw + turn)
        if mode == .wander || mode == .approach || mode == .takeoff {
            bankGoal = simd_clamp(turn / dt * simd_length(v) * 0.12, -0.8, 0.8)
        }
        pitch += (pitchGoal - pitch) * min(1, 6 * dt)
        bank += (bankGoal - bank) * min(1, 5 * dt)
        flight.position = p
        flight.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
            * simd_quatf(angle: bank, axis: [0, 0, 1])
    }

    // MARK: Animation

    private func animate(eye: SIMD3<Float>, dt: Float) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        let nearHand = mode == .approach && simd_distance(p, perchPoint) < 0.7

        // Wing beat. Finch flight: bursts of flaps, then a short bound with the wings tucked.
        var hz: Float = 12, up: Float = 1.15, down: Float = -0.75, weightGoal: Float = 1
        switch mode {
        case .wander:
            bound += dt
            let climbing = v.y > 0.5 || abs(bank) > 0.45
            let period: Float = 0.85
            if bound > period { bound -= period }
            weightGoal = climbing || reduce ? 1 : (bound < 0.5 ? 1 : 0)
        case .approach:
            hz = nearHand ? 14 : 12
        case .land:
            hz = 15; up = 1.25; down = -0.9
        case .takeoff:
            hz = 16
        case .perch:
            hz = 9; up = -0.1 + 0.7 * balance; down = -0.6
            weightGoal = balance > 0.05 ? balance : 0
        }
        flapPhase = (flapPhase + hz * dt).truncatingRemainder(dividingBy: 1)
        flapWeight += (weightGoal - flapWeight) * min(1, 14 * dt)
        let cyc = cycle(flapPhase, up: up, down: down)
        let restFlap: Float = -0.55
        flap = restFlap + (cyc.flap - restFlap) * flapWeight
        fold = 1 + (cyc.fold - 1) * flapWeight
        handCurl = -0.35 * sin(2 * .pi * flapPhase) * flapWeight

        // ~45 wing entities: write transforms only when the wing pose moved (a calm perch holds still).
        let wingPose = SIMD3<Float>(flap, fold, handCurl)
        if !(simd_reduce_max(abs(wingPose - lastWingPose)) <= 1e-3) {
            lastWingPose = wingPose
            poseWings()
        }

        // Legs out for the hand, tucked in flight.
        let legsGoal: Float = mode == .perch || mode == .land || nearHand ? 1 : 0
        legsOut += (legsGoal - legsOut) * min(1, 9 * dt)
        legs.isEnabled = legsOut > 0.05
        legs.scale = [1, max(legsOut, 0.05), 1]
        legs.orientation = simd_quatf(angle: (1 - legsOut) * 0.9, axis: [1, 0, 0])

        // Tail: spread to brake, closed in cruise, flicks when perched.
        var spreadGoal: Float = 0.12
        if mode == .land || nearHand { spreadGoal = 0.6 } else if mode == .takeoff { spreadGoal = 0.4 }
        spreadGoal += min(abs(bank), 0.6) * 0.4
        var lift: Float = mode == .land ? -0.35 : 0
        if flickT >= 0 {
            flickT += dt
            let u = flickT / 0.26
            if u >= 1 { flickT = -1 } else { lift -= 0.55 * sin(.pi * u); spreadGoal += 0.3 * sin(.pi * u) }
        }
        tailSpread += (spreadGoal - tailSpread) * min(1, 12 * dt)
        tailLift += (lift - tailLift) * min(1, 18 * dt)
        tail.orientation = simd_quatf(angle: 0.12 + tailLift, axis: [1, 0, 0])
        for (i, f) in tailFeathers.enumerated() {
            let k = (Float(i) - Self.tailMid) / Self.tailMid
            f.orientation = simd_quatf(angle: k * tailSpread * 0.7, axis: [0, 1, 0])
        }

        // Body: perched birds sit nose-up; breathing; puff after landing, chirping and petting.
        let tiltGoal: Float = mode == .perch ? 0.24 : 0
        perchTilt += (tiltGoal - perchTilt) * min(1, 6 * dt)
        var lift2: Float = 0
        if hopT >= 0 {
            hopT += dt
            let u = hopT / 0.22
            if u >= 1 { hopT = -1 } else { lift2 = 0.018 * sin(.pi * u) }
        }
        var bob: Float = 0
        if mode == .wander, !reduce { bob = 0.05 * sin(2 * .pi * bound / 0.85) }
        poseNode.position = [0, lift2 + bob, 0]
        poseNode.orientation = simd_quatf(angle: perchTilt, axis: [1, 0, 0])
        puff = max(0, puff - dt * 1.6)
        balance = max(0, balance - dt * 1.5)
        happy = max(0, happy - dt * 0.7)
        let breathe = 0.018 * sin(2 * .pi * 1.7 * clock)
        let fluff = 1 + breathe + 0.10 * puff
        body.scale = [fluff, fluff, 1 + breathe * 0.5 + 0.04 * puff]

        // Beak opens with each call.
        var open: Float = 0
        if beakT >= 0 {
            beakT += dt
            let u = beakT / 0.15
            if u >= 1 { beakT = -1 } else { open = sin(.pi * u) }
        }
        lowerBeak.orientation = simd_quatf(angle: -0.45 * open, axis: [1, 0, 0])

        // Blink, and a happy squint while petted.
        blinkIn -= dt
        if blinkIn <= 0 { blinkT = 0; blinkIn = .random(in: 1.8...5, using: &rng) }
        var lid: Float = 1
        if blinkT >= 0 {
            blinkT += dt
            let u = blinkT / 0.13
            if u >= 1 { blinkT = -1 } else { lid = 1 - 0.9 * sin(.pi * u) }
        }
        lid = min(lid, 1 - 0.75 * min(happy * 1.5, 1))
        for e in eyes { e.scale = [1, max(lid, 0.08), 1] }

        // Head: quick saccades with holds, curious tilts, looks at the participant often.
        lookIn -= dt
        switch mode {
        case .perch:
            if lookIn <= 0 {
                let r = Float.random(in: 0...1, using: &rng)
                if r < (attentive ? 0.85 : 0.55) {
                    lookAt = eye
                } else {
                    lookAt = p + [.random(in: -1...1, using: &rng), .random(in: -0.2...0.6, using: &rng),
                                  .random(in: -1...1, using: &rng)]
                }
                rollGoal = Float.random(in: 0...1, using: &rng) < 0.5 ? .random(in: -0.4...0.4, using: &rng) : 0
                lookIn = .random(in: 0.5...1.8, using: &rng)
            }
        case .approach, .land:
            lookAt = perchPoint
            rollGoal = 0
        default:
            lookAt = p + v
            rollGoal = 0
        }
        var yawGoal: Float = 0, pitchGoal: Float = 0
        if let target = lookAt {
            let local = poseNode.convert(position: target, from: nil) - Self.headPivot
            let h = simd_length(SIMD2<Float>(local.x, local.z))
            yawGoal = simd_clamp(atan2(-local.x, -local.z), -1.9, 1.9)
            pitchGoal = simd_clamp(atan2(local.y, max(h, 1e-3)), -0.6, 0.7)
        }
        let snap = min(1, 24 * dt)
        headYaw += (yawGoal - headYaw) * snap
        headPitch += (pitchGoal - headPitch) * snap
        headRoll += (rollGoal - headRoll) * min(1, 10 * dt)
        head.orientation = simd_quatf(angle: headYaw, axis: [0, 1, 0])
            * simd_quatf(angle: headPitch, axis: [1, 0, 0])
            * simd_quatf(angle: headRoll, axis: [0, 0, 1])
    }

    /// Twig grows in with a little overshoot when summoned and shrinks once the bird has left it.
    private func growTwig(dt: Float) {
        let goal: Float = pinned != nil || mode == .perch || mode == .land ? 1 : 0
        if goal == 0, twigGrow < 0.01, twigVel <= 0 {
            twigGrow = 0
            twigVel = 0
            if twig.isEnabled { twig.isEnabled = false }
            return
        }
        twig.isEnabled = true
        twigVel += ((goal - twigGrow) * 160 - twigVel * 16) * dt
        twigGrow += twigVel * dt
        twig.scale = .init(repeating: max(twigGrow, 0.001))
    }

    private static let tailCount = 5
    private static let tailMid = Float(tailCount - 1) / 2

    private static let featherPitch = simd_quatf(angle: 0.05, axis: [1, 0, 0])

    private func poseWings() {
        for w in wings {
            let s = w.side
            w.shoulder.orientation = simd_quatf(angle: s * flap, axis: [0, 0, 1])
                * simd_quatf(angle: -s * fold * 1.5, axis: [0, 1, 0])
            w.hand.orientation = simd_quatf(angle: s * handCurl, axis: [0, 0, 1])
                * simd_quatf(angle: -s * fold * 0.07, axis: [0, 1, 0])
            for (f, spread) in w.feathers {
                let a = spread + (s * .pi / 2 - spread) * fold
                f.orientation = simd_quatf(angle: a, axis: [0, 1, 0]) * Self.featherPitch
            }
        }
    }

    /// Downstroke over 55% of the beat, wings spread; upstroke flexes the wing.
    private func cycle(_ ph: Float, up: Float, down: Float) -> (flap: Float, fold: Float) {
        if ph < 0.55 {
            let e = (1 - cos(.pi * ph / 0.55)) / 2
            return (up + (down - up) * e, 0)
        }
        let u = (ph - 0.55) / 0.45
        let e = (1 - cos(.pi * u)) / 2
        return (down + (up - down) * e, 0.5 * sin(.pi * u))
    }

    private func wrap(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }

    // MARK: Build

    private enum Palette {
        static let body = Dusk.hex(0xFBDAB4)
        static let belly = Dusk.hex(0xFDEBD5)
        static let head = Dusk.hex(0xFCDEBA)
        static let covert = Dusk.hex(0xF4D0A8)
        static let flightA = Dusk.hex(0xE3BC98)
        static let flightB = Dusk.hex(0xD8AB8B)
        static let tail = Dusk.hex(0xDDB290)
        static let beak = Dusk.hex(0xF0A868)
        static let legs = Dusk.hex(0xD9A99B)
        static let eye = Dusk.hex(0x121014)
        static let blush = Dusk.hex(0xF4A08A)
        /// Guide twig. Warm bark and a muted sage leaf: scenery, clear of every game signal color.
        static let bark = Dusk.hex(0x6A5249)
        static let twigLeaf = Dusk.hex(0x9DAE8C)
    }

    // Shared meshes and materials: one resource per shape and color, built once per process.
    private static var meshCache: [String: MeshResource] = [:]
    private static var materialCache: [String: PhysicallyBasedMaterial] = [:]

    private static func cached(_ key: String, _ make: () -> MeshResource?) -> MeshResource? {
        if let m = meshCache[key] { return m }
        let m = make()
        meshCache[key] = m
        return m
    }

    /// Low-poly style: few rings and segments, flat-shaded facets.
    private static func blob(_ radii: SIMD3<Float>, taper: Float, rings: Int = 6, segments: Int = 10) -> MeshResource? {
        cached("blob\(radii)\(taper)\(rings)\(segments)") {
            Meshes.facetBlob(radii: radii, taper: taper, rings: rings, segments: segments)
        }
    }

    private static func feather(length: Float, width: Float, curl: Float) -> MeshResource? {
        cached("feather\(length),\(width),\(curl)") { Meshes.facetFeather(length: length, width: width, curl: curl) }
    }

    private static func pyramid(height: Float, radius: Float, sides: Int) -> MeshResource? {
        cached("pyramid\(height),\(radius),\(sides)") { Meshes.facetCone(height: height, radius: radius, sides: sides) }
    }

    private static func plumage(_ c: UIColor, rough: Float = 0.82) -> PhysicallyBasedMaterial {
        let key = "\(c.description)\(rough)"
        if let m = materialCache[key] { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: rough)
        m.metallic = 0.0
        m.emissiveColor = .init(color: c)
        m.emissiveIntensity = 0.26
        materialCache[key] = m
        return m
    }

    private func build() {
        poseNode.addChild(body)

        // Body, belly, neck.
        if let m = Self.blob([0.030, 0.033, 0.047], taper: 0.45) {
            let e = ModelEntity(mesh: m, materials: [Self.plumage(Palette.body)])
            e.position = [0, 0.046, 0.004]
            body.addChild(e)
        }
        if let m = Self.blob([0.025, 0.026, 0.032], taper: 0.2, rings: 6, segments: 10) {
            let e = ModelEntity(mesh: m, materials: [Self.plumage(Palette.belly, rough: 0.9)])
            e.position = [0, 0.037, -0.0125]
            body.addChild(e)
        }
        if let m = Self.blob([0.024, 0.024, 0.024], taper: 0, rings: 6, segments: 10) {
            let e = ModelEntity(mesh: m, materials: [Self.plumage(Palette.body)])
            e.position = [0, 0.070, -0.021]
            body.addChild(e)
        }

        // Head: large and round for a young-bird look.
        head.position = Self.headPivot
        poseNode.addChild(head)
        let hc = Self.headCenter
        if let m = Self.blob([0.026, 0.025, 0.027], taper: 0, rings: 7, segments: 12) {
            let e = ModelEntity(mesh: m, materials: [Self.plumage(Palette.head)])
            e.position = hc
            head.addChild(e)
        }
        var gloss = PhysicallyBasedMaterial()
        gloss.baseColor = .init(tint: Palette.eye)
        gloss.roughness = 0.06
        gloss.clearcoat = .init(floatLiteral: 1)
        gloss.clearcoatRoughness = .init(floatLiteral: 0.02)
        let catchlight = Look.flat(.white)
        let blush = Look.veil(Palette.blush, opacity: 0.55)
        let eyeball = Self.cached("eye") { .generateSphere(radius: 0.0072) }
        let glints = [Self.cached("glint0") { .generateSphere(radius: 0.0019) },
                      Self.cached("glint1") { .generateSphere(radius: 0.0009) }]
        let cheek = Self.cached("cheek") { Meshes.ellipse(width: 0.012, height: 0.008, segments: 6) }
        for s in [Float(-1), 1] {
            let dir = simd_normalize(SIMD3<Float>(s * 0.62, 0.22, -0.75))
            let eye = Entity()
            eye.position = hc + dir * 0.0225
            eye.orientation = simd_quatf(from: [0, 0, 1], to: dir)
            head.addChild(eye)
            if let eyeball { eye.addChild(ModelEntity(mesh: eyeball, materials: [gloss])) }
            for (off, mesh) in zip([SIMD3<Float>(0.0018 * s, 0.0026, 0.0052), SIMD3<Float>(-0.0016 * s, -0.0018, 0.0058)], glints) {
                guard let mesh else { continue }
                let c = ModelEntity(mesh: mesh, materials: [catchlight])
                c.position = off
                eye.addChild(c)
            }
            eyes.append(eye)

            let cheekDir = simd_normalize(SIMD3<Float>(s * 0.82, -0.2, -0.45))
            if let disc = cheek {
                let c = ModelEntity(mesh: disc, materials: [blush])
                c.position = hc + cheekDir * 0.0264
                c.orientation = simd_quatf(from: [0, 0, 1], to: cheekDir)
                head.addChild(c)
            }
        }
        // Beak: short conical seed-eater bill, lower mandible hinged.
        let beakMat = Self.plumage(Palette.beak, rough: 0.45)
        guard let upperMesh = Self.pyramid(height: 0.013, radius: 0.0058, sides: 5),
              let lowerMesh = Self.pyramid(height: 0.010, radius: 0.0044, sides: 5) else { return }
        let upper = ModelEntity(mesh: upperMesh, materials: [beakMat])
        upper.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        upper.scale = [1, 1, 0.8]
        upper.position = hc + [0, -0.002, -0.031]
        head.addChild(upper)
        lowerBeak.position = hc + [0, -0.006, -0.024]
        head.addChild(lowerBeak)
        let lower = ModelEntity(mesh: lowerMesh, materials: [beakMat])
        lower.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        lower.scale = [1, 1, 0.7]
        lower.position = [0, 0, -0.005]
        lowerBeak.addChild(lower)
        // Crest tuft.
        if let m = Self.feather(length: 0.013, width: 0.006, curl: -0.25) {
            for k in -1...1 {
                let f = ModelEntity(mesh: m, materials: [Self.plumage(Palette.head)])
                f.position = hc + [Float(k) * 0.003, 0.023, -0.008]
                f.orientation = simd_quatf(angle: Float(k) * 0.3, axis: [0, 1, 0]) * simd_quatf(angle: -0.75, axis: [1, 0, 0])
                head.addChild(f)
            }
        }

        // Wings.
        for s in [Float(-1), 1] { wings.append(wing(side: s)) }

        // Tail.
        tail.position = [0, 0.040, 0.042]
        poseNode.addChild(tail)
        if let m = Self.feather(length: 0.05, width: 0.015, curl: 0.05) {
            for i in 0..<Self.tailCount {
                let f = ModelEntity(mesh: m, materials: [Self.plumage(i % 2 == 0 ? Palette.tail : Palette.flightB)])
                f.position = [0, abs(Float(i) - Self.tailMid) * -0.0005, 0]
                tail.addChild(f)
                tailFeathers.append(f)
            }
        }

        // Legs and toes.
        legs.position = [0, 0, 0.004]
        poseNode.addChild(legs)
        let legMat = Self.plumage(Palette.legs, rough: 0.6)
        for s in [Float(-1), 1] {
            let leg = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.0016), materials: [legMat])
            leg.position = [s * 0.009, 0.012, 0]
            legs.addChild(leg)
            for (k, a) in [Float(-0.4), 0, 0.4, .pi].enumerated() {
                let len: Float = k == 3 ? 0.008 : 0.011
                let toe = ModelEntity(mesh: .generateBox(width: 0.0022, height: 0.0018, depth: len, cornerRadius: 0.0009),
                                      materials: [legMat])
                let dir = SIMD3<Float>(sin(a), 0, -cos(a))
                toe.position = [s * 0.009, 0.0012, 0] + dir * (len / 2)
                toe.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
                legs.addChild(toe)
            }
        }
    }

    /// Low-poly branch: origin at the perch point (top of the bark), main limb across local X, a side
    /// shoot and three leaves. Bark and leaf colors come from the valley trees, so it reads as scenery.
    private func buildTwig() {
        let bark = Self.plumage(Palette.bark, rough: 0.95)
        let leaf = Self.plumage(Palette.twigLeaf, rough: 0.85)
        let r: Float = 0.0075
        let limb = Entity()
        limb.position = [0, -r, 0]
        limb.orientation = simd_quatf(angle: 0.08, axis: [0, 0, 1])
        twig.addChild(limb)
        if let m = Self.cached("twigLimb") { Meshes.facetBranch(length: 0.27, r0: r, r1: 0.0035, sides: 6) } {
            let e = ModelEntity(mesh: m, materials: [bark])
            e.position = [-0.12, 0, 0]
            limb.addChild(e)
        }
        if let m = Self.cached("twigShoot") { Meshes.facetBranch(length: 0.075, r0: 0.0042, r1: 0.002, sides: 5) } {
            let e = ModelEntity(mesh: m, materials: [bark])
            e.position = [-0.075, 0.002, 0]
            e.orientation = simd_quatf(angle: 2.3, axis: [0, 0, 1])
            limb.addChild(e)
        }
        guard let m = Self.feather(length: 0.05, width: 0.024, curl: 0.18) else { return }
        // (position on the limb, heading around Y, droop)
        let leaves: [(SIMD3<Float>, Float, Float)] = [
            ([0.145, 0, 0], .pi / 2, 0.35),
            ([0.08, 0.002, 0.002], 0.35, 0.55),
            ([-0.123, 0.052, 0], -.pi / 2, -0.5),
        ]
        for (pos, heading, droop) in leaves {
            let e = ModelEntity(mesh: m, materials: [leaf])
            e.position = pos
            e.orientation = simd_quatf(angle: heading, axis: [0, 1, 0]) * simd_quatf(angle: droop, axis: [1, 0, 0])
            limb.addChild(e)
        }
    }

    /// Two-segment wing: arm with secondaries and coverts, hand with primaries. Spread pose lies in the
    /// XZ plane, span along +X times `side`, feathers trailing +Z. Folding sweeps the arm back and turns
    /// every feather to lie along the span, so the folded wing rests over the back and side.
    private func wing(side s: Float) -> Wing {
        let shoulder = Entity()
        shoulder.position = [s * 0.022, 0.062, -0.012]
        poseNode.addChild(shoulder)
        let hand = Entity()
        hand.position = [s * 0.030, 0, 0]
        shoulder.addChild(hand)
        var feathers: [(Entity, Float)] = []

        if let arm = Self.blob([0.017, 0.005, 0.007], taper: 0, rings: 4, segments: 6) {
            let e = ModelEntity(mesh: arm, materials: [Self.plumage(Palette.covert)])
            e.position = [s * 0.015, 0.001, 0.001]
            shoulder.addChild(e)
        }
        if let arm = Self.blob([0.015, 0.004, 0.005], taper: 0, rings: 4, segments: 6) {
            let e = ModelEntity(mesh: arm, materials: [Self.plumage(Palette.covert)])
            e.position = [s * 0.013, 0.001, 0]
            hand.addChild(e)
        }
        // Secondaries.
        for i in 0..<4 {
            guard let m = Self.feather(length: 0.042 + Float(i) * 0.002, width: 0.016, curl: 0.06) else { continue }
            let f = ModelEntity(mesh: m, materials: [Self.plumage(i % 2 == 0 ? Palette.flightA : Palette.flightB)])
            f.position = [s * (0.004 + Float(i) * 0.0072), -0.001 - Float(i) * 0.0003, 0.002]
            shoulder.addChild(f)
            feathers.append((f, s * Float(i) * 0.045))
        }
        // Coverts over the secondaries.
        for i in 0..<3 {
            guard let m = Self.feather(length: 0.022, width: 0.017, curl: 0.04) else { continue }
            let f = ModelEntity(mesh: m, materials: [Self.plumage(Palette.covert)])
            f.position = [s * (0.005 + Float(i) * 0.010), 0.0025, -0.002]
            shoulder.addChild(f)
            feathers.append((f, s * Float(i) * 0.06))
        }
        // Primaries, fanning out to the wing tip.
        for i in 0..<5 {
            let len = 0.05 + 0.014 * sin(Float(i) / 4 * .pi * 0.8)
            guard let m = Self.feather(length: len, width: 0.014, curl: 0.07) else { continue }
            let f = ModelEntity(mesh: m, materials: [Self.plumage(i % 2 == 0 ? Palette.flightB : Palette.flightA)])
            f.position = [s * (0.002 + Float(i) * 0.0059), -0.0015 - Float(i) * 0.0003, 0.001]
            hand.addChild(f)
            feathers.append((f, s * (0.15 + Float(i) * 0.24)))
        }
        // Primary coverts.
        for i in 0..<2 {
            guard let m = Self.feather(length: 0.02, width: 0.015, curl: 0.04) else { continue }
            let f = ModelEntity(mesh: m, materials: [Self.plumage(Palette.covert)])
            f.position = [s * (0.004 + Float(i) * 0.011), 0.002, -0.001]
            hand.addChild(f)
            feathers.append((f, s * (0.2 + Float(i) * 0.38)))
        }
        return Wing(side: s, shoulder: shoulder, hand: hand, feathers: feathers)
    }
}

extension Meshes {
    /// Low-poly ellipsoid: same shape rule as `blob`, flat-shaded facets. Odd ring rows are offset half a
    /// segment so the facets read as triangles in a gem pattern instead of a quad grid.
    static func facetBlob(radii: SIMD3<Float>, taper: Float, rings: Int, segments: Int) -> MeshResource? {
        func point(_ r: Int, _ s: Float) -> SIMD3<Float> {
            let phi = Float(r) / Float(rings) * .pi
            let th = (s + (r % 2 == 1 ? 0.5 : 0)) / Float(segments) * 2 * .pi
            let n = SIMD3<Float>(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
            let k = 1 - taper * pow(max(0, n.z), 1.5)
            return [n.x * radii.x * k, n.y * radii.y * k, n.z * radii.z]
        }
        // Pole triangles collapse to zero area and are dropped in `faceted`.
        var tris: [SIMD3<Float>] = []
        for r in 0..<rings {
            for i in 0..<segments {
                let a0 = point(r, Float(i)), a1 = point(r, Float(i + 1))
                let b0 = point(r + 1, Float(i)), b1 = point(r + 1, Float(i + 1))
                if r % 2 == 0 {
                    tris += [a0, a1, b0, a1, b1, b0]  // next ring sits half a segment ahead
                } else {
                    tris += [a0, a1, b1, a0, b1, b0]  // next ring sits half a segment behind
                }
            }
        }
        return faceted(tris, name: "facetBlob", twoSided: false)
    }

    /// Low-poly feather: a five-point blade (quill, two shoulders, tip, raised rachis ridge), both faces.
    static func facetFeather(length: Float, width: Float, curl: Float) -> MeshResource? {
        let hw = width / 2
        let quill = SIMD3<Float>(0, 0, 0)
        let lS = SIMD3<Float>(-hw, -0.25 * curl * length - 0.0004, 0.45 * length)
        let rS = SIMD3<Float>(hw, -0.25 * curl * length - 0.0004, 0.45 * length)
        let ridge = SIMD3<Float>(0, -0.2 * curl * length + 0.0008, 0.5 * length)
        let lT = SIMD3<Float>(-hw * 0.55, -0.7 * curl * length - 0.0003, 0.82 * length)
        let rT = SIMD3<Float>(hw * 0.55, -0.7 * curl * length - 0.0003, 0.82 * length)
        let tip = SIMD3<Float>(0, -curl * length, length)
        // Counterclockwise seen from +Y.
        let tris: [SIMD3<Float>] = [quill, ridge, lS, quill, rS, ridge,
                                    lS, ridge, lT, ridge, rS, rT, ridge, rT, lT,
                                    lT, rT, tip]
        return faceted(tris, name: "facetFeather", twoSided: true)
    }

    /// Low-poly tapered prism along +X from 0 to `length`, radius `r0` at the base to `r1` at the tip, capped.
    static func facetBranch(length: Float, r0: Float, r1: Float, sides: Int) -> MeshResource? {
        func ring(_ x: Float, _ r: Float, _ i: Int) -> SIMD3<Float> {
            let a = Float(i) / Float(sides) * 2 * .pi
            return [x, cos(a) * r, sin(a) * r]
        }
        var tris: [SIMD3<Float>] = []
        let base = SIMD3<Float>(0, 0, 0), tip = SIMD3<Float>(length, 0, 0)
        for i in 0..<sides {
            let a0 = ring(0, r0, i), a1 = ring(0, r0, i + 1)
            let b0 = ring(length, r1, i), b1 = ring(length, r1, i + 1)
            tris += [a0, a1, b0, a1, b1, b0, base, a1, a0, tip, b0, b1]
        }
        return faceted(tris, name: "facetBranch", twoSided: false)
    }

    /// Low-poly cone along +Y, base at -height/2, matching `generateCone` placement.
    static func facetCone(height: Float, radius: Float, sides: Int) -> MeshResource? {
        let apex = SIMD3<Float>(0, height / 2, 0), base = SIMD3<Float>(0, -height / 2, 0)
        var tris: [SIMD3<Float>] = []
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi, a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let p0 = SIMD3<Float>(cos(a0) * radius, -height / 2, sin(a0) * radius)
            let p1 = SIMD3<Float>(cos(a1) * radius, -height / 2, sin(a1) * radius)
            tris += [p0, apex, p1, p0, p1, base]
        }
        return faceted(tris, name: "facetCone", twoSided: false)
    }

    /// Unindexed triangle soup with one normal per face. Winding is fixed per triangle so the normal
    /// points away from the mesh centroid, which holds for the convex-ish shapes above.
    static func faceted(_ tris: [SIMD3<Float>], name: String, twoSided: Bool) -> MeshResource? {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        positions.reserveCapacity(tris.count * (twoSided ? 2 : 1))
        let centroid = tris.reduce(SIMD3<Float>.zero, +) / Float(max(1, tris.count))
        for k in stride(from: 0, to: tris.count - 2, by: 3) {
            let a = tris[k]
            var b = tris[k + 1], c = tris[k + 2]
            var n = simd_cross(b - a, c - a)
            guard simd_length(n) > 1e-14 else { continue }
            n = simd_normalize(n)
            if !twoSided, simd_dot(n, (a + b + c) / 3 - centroid) < 0 { swap(&b, &c); n = -n }
            positions += [a, b, c]
            normals += [n, n, n]
            if twoSided {
                positions += [a, c, b]
                normals += [-n, -n, -n]
            }
        }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.primitives = .triangles((0..<UInt32(positions.count)).map { $0 })
        return try? MeshResource.generate(from: [d])
    }
}
