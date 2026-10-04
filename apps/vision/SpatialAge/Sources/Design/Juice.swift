import RealityKit
import simd
import UIKit

/// Reward layer on top of the five micro-interactions: a 3D spark burst, a rising 3D praise word and a bell
/// chime on each success, scaled by a streak of consecutive successes; a confetti shower and fanfare at the
/// end of a block. Spec: specs/games/design.md, Rewards.
///
/// Safety rules, all enforced here:
/// - Effects start only after the trial outcome is recorded, run on tweens and never delay the game loop.
/// - Local only: sparks stay within about 25 cm of the contact, nothing fills the field of view, no strobe
///   (one flash per success, each fading over at least 250 ms).
/// - Words only, never a number from play. A streak shows as a stronger word, never as a count.
/// - Reduce Motion: fewer sparks, no travel, the word fades in place.
/// - Misses stay quiet: a miss only resets the streak.
@MainActor
final class Juice {
    let clock: FrameClock
    let root: Entity
    /// Consecutive successes in the current block.
    private(set) var streak = 0

    init(clock: FrameClock, root: Entity) {
        self.clock = clock
        self.root = root
    }

    /// Streak tier 0 to 3. Drives spark count, chime register and the praise word.
    var tier: Int { switch streak { case ..<3: 0; case 3..<5: 1; case 5..<8: 2; default: 3 } }

    static let words: [[String]] = [
        ["Nice!", "Got it!", "Good!", "Yes!"],
        ["Great!", "Sharp!", "Smooth!"],
        ["On fire!", "Superb!", "Lightning!"],
        ["Unstoppable!", "Legendary!", "Incredible!"],
    ]

    /// Praise word for the current streak.
    var word: String { Self.words[tier].randomElement()! }

    /// Word of the last success, handed once to the HUD so the cue line and the 3D word agree.
    private var lastWord: String?
    func takeWord() -> String? {
        defer { lastWord = nil }
        return lastWord
    }

    /// Success at `at`: counts toward the streak, then burst, chime and a 3D word. Returns the word shown so the
    /// HUD can echo it.
    @discardableResult
    func success(at: SIMD3<Float>, color: UIColor = Theme.gold, word: String? = nil) -> String {
        streak += 1
        let w = word ?? self.word
        lastWord = w
        let anchor = Entity()
        anchor.position = at
        root.addChild(anchor)
        Tone.play(.chime(tier), on: anchor, gain: -13 + Double(tier))
        if tier >= 2 { Tone.play(.sparkle, on: anchor, gain: -20) }
        halo(at: at, color: color, radius: 0.05 + 0.01 * Float(tier))
        burst(at: at, colors: [color, Theme.paper, Theme.gold], count: 10 + 4 * tier, speed: 0.55 + 0.12 * Float(tier))
        popup(w, at: at + [0, 0.09, 0], color: tier >= 2 ? Theme.gold : Theme.paper, size: 0.045 + 0.006 * Float(tier))
        clock.animate(1.2, { _ in }, done: { anchor.removeFromParent() })
        return w
    }

    /// Partial success inside a trial (one recalled ball of several): small burst and the halo, no word or
    /// chime, streak unchanged. The trial's full `success` comes once at the end.
    func tap(at: SIMD3<Float>, color: UIColor = Theme.gold) {
        halo(at: at, color: color, radius: 0.04)
        burst(at: at, colors: [color, Theme.paper], count: 6, speed: 0.4)
    }

    /// Miss, wrong touch or timeout: the streak ends. No sound or visual here; `Micro.sink` keeps its quiet tone.
    func reset() {
        streak = 0
        lastWord = nil
    }

    /// End of a block: confetti shower and fanfare at `at` (past arm's reach, in front of the participant).
    func finale(at: SIMD3<Float>, big: Bool) {
        let anchor = Entity()
        anchor.position = at
        root.addChild(anchor)
        Tone.play(big ? .fanfare : .chime(1), on: anchor, gain: big ? -10 : -14)
        let palette = [Theme.go, Theme.gold, Theme.teal, Theme.paper, Theme.nogo]
        if Self.reduceMotion {
            burst(at: at, colors: palette, count: 10, speed: 0)
        } else {
            confetti(at: at + [0, 0.35, 0], colors: palette, count: big ? 46 : 24)
            burst(at: at, colors: palette, count: big ? 22 : 12, speed: 0.9)
        }
        clock.animate(2.2, { _ in }, done: { anchor.removeFromParent() })
        streak = 0
    }

    // MARK: Effects

    private static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private static let sparkMesh = MeshResource.generateSphere(radius: 0.006)
    private static let flakeMesh = MeshResource.generateBox(width: 0.018, height: 0.010, depth: 0.0015)
    private static var materials: [UIColor: UnlitMaterial] = [:]
    private static var textMeshes: [String: MeshResource] = [:]

    private static func material(_ c: UIColor) -> UnlitMaterial {
        if let m = materials[c] { return m }
        let m = Look.flat(c)
        materials[c] = m
        return m
    }

    private static let haloMesh = MeshResource.generateSphere(radius: 1)

    /// Soft glowing shell that swells from the contact to `radius` and fades over 0.35 s. One flash per success.
    func halo(at: SIMD3<Float>, color: UIColor, radius: Float) {
        let e = ModelEntity(mesh: Self.haloMesh, materials: [Self.material(color)])
        e.position = at
        e.components.set(OpacityComponent(opacity: 0.45))
        root.addChild(e)
        let still = Self.reduceMotion
        clock.animate(0.35, { p in
            let q = Float(Ease.out(p))
            e.scale = .init(repeating: radius * (still ? 1 : 0.3 + 0.7 * q))
            e.components[OpacityComponent.self]?.opacity = 0.45 * (1 - q)
        }, done: { e.removeFromParent() })
    }

    /// The word on screen. A new word replaces it, so words never stack in view.
    private var livePopup: Entity?

    /// Sparks fly out on a sphere, slow with drag, fall a little and fade over 0.6 s. One tween drives them all.
    func burst(at: SIMD3<Float>, colors: [UIColor], count: Int, speed: Float) {
        let still = Self.reduceMotion
        let n = still ? min(count, 6) : count
        var sparks: [(e: ModelEntity, v: SIMD3<Float>)] = []
        for k in 0..<n {
            let e = ModelEntity(mesh: Self.sparkMesh, materials: [Self.material(colors[k % colors.count])])
            e.components.set(OpacityComponent(opacity: 1))
            // Golden-angle spiral: even coverage without randomness.
            let y = 1 - 2 * (Float(k) + 0.5) / Float(n)
            let r = (1 - y * y).squareRoot(), a = Float(k) * 2.39996
            let dir = SIMD3<Float>(cos(a) * r, y * 0.8 + 0.2, sin(a) * r)
            let v = still ? .zero : dir * speed * Float.random(in: 0.7...1.2)
            e.position = at + (still ? dir * 0.05 : .zero)
            e.scale = .init(repeating: Float.random(in: 0.8...1.5))
            root.addChild(e)
            sparks.append((e, v))
        }
        let s0 = sparks.map(\.e.scale)
        clock.animate(0.6, { p in
            let t = Float(p * 0.6)
            // x(t) with linear drag k = 4 and gentle gravity.
            let travel = (1 - exp(-4 * t)) / 4
            for (i, s) in sparks.enumerated() {
                s.e.position = at + s.v * travel + SIMD3<Float>(0, -0.35 * t * t, 0)
                s.e.scale = s0[i] * Float(1 - 0.6 * p)
                s.e.components[OpacityComponent.self]?.opacity = Float(1 - p * p)
            }
        }, done: { sparks.forEach { $0.e.removeFromParent() } })
    }

    /// Paper flakes drift down while tumbling, 1.8 s.
    private func confetti(at: SIMD3<Float>, colors: [UIColor], count: Int) {
        var flakes: [(e: ModelEntity, v: SIMD3<Float>, spin: SIMD3<Float>, phase: Float)] = []
        for k in 0..<count {
            let e = ModelEntity(mesh: Self.flakeMesh, materials: [Self.material(colors[k % colors.count])])
            e.components.set(OpacityComponent(opacity: 1))
            e.position = at
            let a = Float.random(in: 0...(2 * .pi))
            let v = SIMD3<Float>(cos(a) * .random(in: 0.2...0.7), .random(in: 0.3...0.9), sin(a) * .random(in: 0.1...0.4))
            let spin = simd_normalize(SIMD3<Float>(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1)) + 1e-3)
            root.addChild(e)
            flakes.append((e, v, spin, .random(in: 0...6)))
        }
        clock.animate(1.8, { p in
            let t = Float(p * 1.8)
            let travel = (1 - exp(-3 * t)) / 3
            for f in flakes {
                let flutter = SIMD3<Float>(0.03 * sin(5 * t + f.phase), 0, 0)
                f.e.position = at + f.v * travel + SIMD3<Float>(0, -0.18 * t * t, 0) + flutter
                f.e.orientation = simd_quatf(angle: 9 * t + f.phase, axis: f.spin)
                f.e.components[OpacityComponent.self]?.opacity = Float(p < 0.6 ? 1 : 1 - (p - 0.6) / 0.4)
            }
        }, done: { flakes.forEach { $0.e.removeFromParent() } })
    }

    /// Extruded 3D word that springs in, rises 10 cm toward the viewer's eye line and fades, 0.85 s.
    func popup(_ text: String, at: SIMD3<Float>, color: UIColor, size: Float) {
        let mesh: MeshResource
        if let m = Self.textMeshes[text] {
            mesh = m
        } else {
            mesh = MeshResource.generateText(text, extrusionDepth: 0.12, font: .systemFont(ofSize: 1, weight: .heavy),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
            Self.textMeshes[text] = mesh
        }
        let glyphs = ModelEntity(mesh: mesh, materials: [Look.glow(color, intensity: 1.4)])
        glyphs.position = -mesh.bounds.center
        let holder = Entity()
        holder.addChild(glyphs)
        let pivot = Entity()
        pivot.position = at
        pivot.components.set(BillboardComponent())
        pivot.components.set(OpacityComponent(opacity: 1))
        pivot.addChild(holder)
        livePopup?.removeFromParent()
        livePopup = pivot
        root.addChild(pivot)
        let still = Self.reduceMotion
        clock.animate(0.85, { p in
            let pop = still ? 1 : Float(Ease.back(min(p / 0.3, 1)))
            holder.scale = .init(repeating: max(size * pop, 1e-4))
            pivot.position = at + [0, still ? 0 : 0.10 * Float(Ease.out(p)), 0]
            pivot.components[OpacityComponent.self]?.opacity = Float(p < 0.55 ? 1 : 1 - (p - 0.55) / 0.45)
        }, done: { [weak self] in
            pivot.removeFromParent()
            if self?.livePopup === pivot { self?.livePopup = nil }
        })
    }
}
