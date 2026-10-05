import RealityKit
import ScoreKit
import UIKit

/// Estimated age from one game's scored block, shown by `GameAgeReveal` and read out by Buddy.
struct GameAge {
    let game: Game
    /// Whole years, clamped to the model range.
    let years: Int
    /// Estimate minus chronological age, years. Negative is younger. Nil without a chronological age.
    let gap: Double?

    /// Scores a copy of the session holding only this game's scored blocks.
    @MainActor
    static func estimate(_ game: Game, session: Session) -> GameAge? {
        var s = session
        s.blocks = session.blocks.filter { $0.task == game.task && !$0.familiarization }
        guard !s.blocks.isEmpty else { return nil }
        let report = ScoreEngine().score(s)
        guard let age = report.spatialAge ?? report.evidenceAge, age.isFinite else { return nil }
        return GameAge(game: game, years: Int(age.rounded()), gap: report.ageGap)
    }

    /// Buddy's bubbles after the reveal. The last one hands over to the next game, if any.
    func lines(next: Game?) -> [String] {
        var out = ["Your \(game.duskTitle) age is \(years)!"]
        if let gap {
            let k = Int(abs(gap).rounded())
            switch gap {
            case ...(-4.5): out.append("That's \(k) years younger than you. Amazing!")
            case ..<(-0.5): out.append("That's \(k) year\(k == 1 ? "" : "s") younger than you. Nice!")
            case ...0.5: out.append("Right on your age. Solid round!")
            default: out.append("That's \(k) year\(k == 1 ? "" : "s") older. The next one is a fresh start.")
            }
        } else {
            out.append("Every game adds to your Spatial Age.")
        }
        if let next { out.append("Next up: \(next.duskTitle). Ready?") }
        return out
    }
}

/// End-of-game cinematic. The valley dims, gold rays fan out, and the game age arrives as extruded 3D digits
/// that fly in from the dark, spin and roll like a slot reel, and lock into place one by one with a flash,
/// sparks, a shockwave and the fanfare. Then the number lifts so Buddy can land and talk, and finally bursts
/// into sparks. Everything sits 1.6 m ahead, past arm's reach. Reduce Motion: fades only, no spin or roll.
@MainActor
final class GameAgeReveal {
    private let clock: FrameClock
    private let juice: Juice
    private let parent: Entity

    private let root = Entity()
    private let float = Entity()
    private let rays = Entity()
    private let dim: ModelEntity
    private var disc: ModelEntity?
    private var digits: [(holder: Entity, glyph: ModelEntity)] = []
    private var captions: [Entity] = []
    private var idle: Task<Void, Never>?
    private var removed = false

    /// Digit cap height, meters. About 11 degrees tall at the reveal distance.
    static let capHeight: Float = 0.30
    static let distance: Float = 1.6
    private static var still: Bool { UIAccessibility.isReduceMotionEnabled }

    init(clock: FrameClock, juice: Juice, parent: Entity) {
        self.clock = clock
        self.juice = juice
        self.parent = parent
        var m = UnlitMaterial(color: Theme.ink)
        m.blending = .transparent(opacity: 1.0)
        m.faceCulling = .front
        dim = ModelEntity(mesh: .generateSphere(radius: 2.6), materials: [m])
        dim.components.set(OpacityComponent(opacity: 0))
    }

    // MARK: Sequence

    /// Plays the reveal and returns once every digit has landed and the fanfare has fired (about 2.6 s).
    /// With no estimate it shows "Done!" in the same style.
    func show(_ result: GameAge?, rig: Rig) async {
        dim.position = rig.world([0, rig.eye, 0])
        parent.addChild(dim)
        root.position = rig.world([0, rig.eye + 0.02, -Self.distance])
        root.orientation = rig.rotation
        root.addChild(rays)
        root.addChild(float)
        parent.addChild(root)

        let still = Self.still
        clock.animate(0.7, { [dim] p in dim.components[OpacityComponent.self]?.opacity = Float(0.55 * Ease.out(p)) })
        Tone.play(.whirr, on: root, gain: -14)
        buildBackdrop()
        clock.animate(still ? 0.3 : 0.9, { [rays, disc] p in
            let e = Float(Ease.out(p))
            rays.scale = .init(repeating: max(still ? 1 : e, 1e-3))
            rays.components[OpacityComponent.self]?.opacity = e
            disc?.components[OpacityComponent.self]?.opacity = 0.32 * e
        })

        let text = result.map { String($0.years) } ?? "Done!"
        let title = result.map { "YOUR \($0.game.duskTitle.uppercased()) AGE" } ?? ""
        if !title.isEmpty { caption(title, y: Self.capHeight * 0.92, height: 0.034, color: Theme.paper, delay: 0.25) }
        await clock.wait(0.35)

        let glyphs = Array(text)
        let s = Self.capHeight / Float(Self.font.capHeight)
        let advance = Self.advance * s
        let total = advance * Float(glyphs.count)
        let stagger = still ? 0.05 : 0.24
        let flight = still ? 0.35 : 1.05
        for (i, ch) in glyphs.enumerated() {
            let holder = Entity()
            holder.components.set(OpacityComponent(opacity: 0))
            let glyph = ModelEntity(mesh: Self.mesh(ch).mesh, materials: Self.materials(flash: false))
            glyph.scale = .init(repeating: s)
            Self.center(glyph, on: ch, scale: s)
            holder.addChild(glyph)
            float.addChild(holder)
            digits.append((holder, glyph))
            let home = SIMD3<Float>(-total / 2 + advance * (Float(i) + 0.5), 0, 0)
            fly(holder, glyph: glyph, to: home, final: ch, scale: s, delay: Double(i) * stagger, duration: flight,
                rolls: ch.isNumber)
        }
        await clock.wait(Double(max(glyphs.count - 1, 0)) * stagger + flight + 0.05)
        guard !Task.isCancelled else { return }

        // All locked: shockwave, fanfare and confetti, then the comparison line.
        shockwave()
        juice.finale(at: root.position + rig.rotation.act([0, 0.05, 0.25]), big: true)
        if let line = result.flatMap(Self.subline) {
            caption(line.text, y: -Self.capHeight * 0.88, height: 0.042, color: line.color, delay: 0.3)
            Task { @MainActor [clock, root] in
                await clock.wait(0.3)
                Tone.play(.chime(3), on: root, gain: -15)
            }
        }
        startIdle()
        await clock.wait(0.5)
    }

    /// Raises the number above Buddy's bubble and pushes it back a little, 0.8 s.
    func lift(_ rig: Rig) {
        let from = root.position, to = rig.world([0, rig.eye + 0.42, -Self.distance - 0.3])
        let s0 = root.scale.x
        clock.animate(Self.still ? 0.3 : 0.8, { [root] p in
            let e = Float(Ease.inOut(p))
            root.position = simd_mix(from, to, SIMD3(repeating: e))
            root.scale = .init(repeating: s0 + (0.72 - s0) * e)
        })
    }

    /// Digits burst into sparks, rays fold, the valley brightens. Removes everything when done (0.75 s).
    func dissolve() async {
        guard !removed else { return }
        idle?.cancel()
        let palette = [Theme.gold, Theme.paper, Theme.gold, Theme.teal]
        for d in digits { juice.burst(at: d.glyph.position(relativeTo: nil), colors: palette, count: 14, speed: 0.7) }
        Tone.play(.sparkle, on: root, gain: -14)
        let holders = digits.map(\.holder), caps = captions
        let s0 = rays.scale.x
        clock.animate(0.7, { [rays, disc, dim] p in
            let e = Float(Ease.out(p)), fade = Float(1 - p)
            for h in holders {
                h.scale = .init(repeating: 1 + 0.35 * e)
                h.components[OpacityComponent.self]?.opacity = fade * fade
            }
            for c in caps { c.components[OpacityComponent.self]?.opacity = fade }
            rays.scale = .init(repeating: max(s0 * (1 - e), 1e-3))
            disc?.components[OpacityComponent.self]?.opacity = 0.32 * fade
            dim.components[OpacityComponent.self]?.opacity = 0.55 * fade
        })
        await clock.wait(0.75)
        remove()
    }

    /// Removes the reveal at once (skip, exit, cancel).
    func remove() {
        removed = true
        idle?.cancel()
        idle = nil
        root.removeFromParent()
        dim.removeFromParent()
    }

    // MARK: Pieces

    /// One digit's entrance: from 2.4 m further out, high and wide, spinning about its vertical axis and
    /// rolling through random digits; it locks on the true digit at 70 % of the flight and lands with a
    /// squash, a flash and sparks.
    private func fly(_ holder: Entity, glyph: ModelEntity, to home: SIMD3<Float>, final ch: Character, scale s: Float,
                     delay: Double, duration: Double, rolls: Bool) {
        let still = Self.still
        let start = still ? home : home * 1.8 + SIMD3<Float>(0, 0.28, -2.4)
        let spin = Float.pi * 4 * (home.x < 0 ? -1 : 1)
        holder.position = start
        var shown = ch
        var lastRoll = -1.0
        var landed = false
        clock.animate(delay + duration, { [weak self] q in
            let t = q * (delay + duration)
            guard t >= delay else { return }
            let p = (t - delay) / duration
            let e = Float(Ease.out(p))
            holder.position = simd_mix(start, home, SIMD3(repeating: e))
            holder.components[OpacityComponent.self]?.opacity = Float(min(p / 0.25, 1))
            if still {
                holder.scale = .one
            } else {
                holder.orientation = simd_quatf(angle: spin * (1 - e), axis: [0, 1, 0])
                    * simd_quatf(angle: 0.25 * (1 - e), axis: [1, 0, 0])
                holder.scale = .init(repeating: 0.25 + 0.75 * e)
            }
            // Slot-reel roll: a new random digit every 55 ms until the lock point.
            if rolls, !still {
                if p < 0.7, t - lastRoll > 0.055 {
                    lastRoll = t
                    var r = Character(String(Int.random(in: 0...9)))
                    if r == shown { r = Character(String((Int(String(r))! + 1) % 10)) }
                    shown = r
                    glyph.model?.mesh = Self.mesh(r).mesh
                    Self.center(glyph, on: r, scale: s)
                    if Int(t * 1000) % 3 == 0 { Tone.play(.tock, on: holder, gain: -30) }
                } else if p >= 0.7, shown != ch {
                    shown = ch
                    glyph.model?.mesh = Self.mesh(ch).mesh
                    Self.center(glyph, on: ch, scale: s)
                }
            }
            if p >= 1, !landed {
                landed = true
                self?.land(holder, glyph: glyph)
            }
        })
    }

    private func land(_ holder: Entity, glyph: ModelEntity) {
        Tone.play(.lock, on: holder, gain: -12)
        glyph.model?.materials = Self.materials(flash: true)
        juice.burst(at: holder.position(relativeTo: nil), colors: [Theme.gold, Theme.paper], count: 12, speed: 0.55)
        guard !Self.still else {
            glyph.model?.materials = Self.materials(flash: false)
            return
        }
        clock.animate(0.32, { p in
            // Squash 1.18 wide, 0.86 tall, spring back.
            let k = Float(sin(p * .pi) * (1 - p))
            holder.scale = [1 + 0.18 * k, 1 - 0.14 * k, 1 + 0.18 * k]
        }, done: {
            holder.scale = .one
            glyph.model?.materials = Self.materials(flash: false)
        })
    }

    /// Glow disc and a fan of gold rays behind the number.
    private func buildBackdrop() {
        rays.position = [0, 0, -0.12]
        rays.components.set(OpacityComponent(opacity: 0))
        rays.scale = .init(repeating: 1e-3)
        var ray = UnlitMaterial(color: Theme.gold)
        ray.blending = .transparent(opacity: .init(floatLiteral: 0.16))
        ray.faceCulling = .none
        let count = 16
        for k in 0..<count {
            let len: Float = k % 2 == 0 ? 1.15 : 0.7
            let spoke = Entity()
            spoke.orientation = simd_quatf(angle: Float(k) / Float(count) * 2 * .pi, axis: [0, 0, 1])
            let plane = ModelEntity(mesh: .generatePlane(width: k % 2 == 0 ? 0.022 : 0.014, height: len), materials: [ray])
            plane.position = [0, 0.16 + len / 2, 0]
            spoke.addChild(plane)
            rays.addChild(spoke)
        }
        if let mesh = Meshes.ellipse(width: 1.1, height: 0.8) {
            var m = UnlitMaterial(color: Theme.gold)
            m.blending = .transparent(opacity: 1.0)
            m.faceCulling = .none
            let d = ModelEntity(mesh: mesh, materials: [m])
            d.position = [0, 0, -0.15]
            d.components.set(OpacityComponent(opacity: 0))
            root.addChild(d)
            disc = d
        }
    }

    /// Thin gold disc that races out from the number and fades, 0.9 s.
    private func shockwave() {
        guard let mesh = Meshes.ellipse(width: 1, height: 1) else { return }
        var m = UnlitMaterial(color: Theme.paper)
        m.blending = .transparent(opacity: 1.0)
        m.faceCulling = .none
        let wave = ModelEntity(mesh: mesh, materials: [m])
        wave.position = [0, 0, -0.05]
        wave.components.set(OpacityComponent(opacity: 0.5))
        root.addChild(wave)
        let still = Self.still
        clock.animate(0.9, { p in
            let e = Float(Ease.out(p))
            wave.scale = .init(repeating: still ? 1.2 : 0.2 + 2.4 * e)
            wave.components[OpacityComponent.self]?.opacity = 0.5 * Float(1 - p) * Float(1 - p)
        }, done: { wave.removeFromParent() })
    }

    /// A line of extruded rounded capitals that rises 3 cm into place and fades in.
    private func caption(_ text: String, y: Float, height: Float, color: UIColor, delay: Double) {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.15, font: Self.font)
        let s = height / Float(Self.font.capHeight)
        let model = ModelEntity(mesh: mesh, materials: [Look.glow(color, intensity: 0.9), Look.glow(Theme.gold, intensity: 0.5)])
        model.scale = .init(repeating: s)
        let b = mesh.bounds
        model.position = -SIMD3<Float>((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2) * s
        let holder = Entity()
        holder.addChild(model)
        holder.components.set(OpacityComponent(opacity: 0))
        float.addChild(holder)
        captions.append(holder)
        let rise: Float = Self.still ? 0 : 0.03
        clock.animate(delay + 0.5, { q in
            let p = max(0, (q * (delay + 0.5) - delay) / 0.5)
            let e = Float(Ease.out(p))
            holder.position = [0, y - rise * (1 - e), 0]
            holder.components[OpacityComponent.self]?.opacity = e
        })
    }

    /// Gentle hover of the number and a slow turn of the rays while the reveal holds.
    private func startIdle() {
        guard !Self.still else { return }
        idle = Task { @MainActor [clock, float, rays] in
            var t = 0.0
            while !Task.isCancelled, !clock.stopped {
                t += await clock.next()
                float.position.y = 0.008 * Float(sin(t * 1.7))
                float.orientation = simd_quatf(angle: 0.05 * Float(sin(t * 0.9)), axis: [0, 1, 0])
                rays.orientation = simd_quatf(angle: Float(t) * 0.12, axis: [0, 0, 1])
            }
        }
    }

    private static func subline(_ r: GameAge) -> (text: String, color: UIColor)? {
        guard let gap = r.gap else { return ("SPATIAL AGE ESTIMATE", Theme.paper) }
        let k = Int(abs(gap).rounded())
        if gap <= -0.5 { return ("\(k) YEAR\(k == 1 ? "" : "S") YOUNGER", Theme.gold) }
        if gap < 0.5 { return ("RIGHT ON YOUR AGE", Theme.paper) }
        return ("\(k) YEAR\(k == 1 ? "" : "S") OLDER", Theme.paper)
    }

    // MARK: Glyphs

    private static let font: UIFont = {
        let base = UIFont.systemFont(ofSize: 1, weight: .heavy)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: 1)
    }()

    /// Fixed digit advance at 1 m font size, so rolling digits never shift the row.
    private static let advance: Float = {
        let w = (0...9).map { d -> Float in let b = mesh(Character(String(d))).bounds; return b.max.x - b.min.x }
        return (w.max() ?? 0.6) + 0.06
    }()

    private static var glyphCache: [Character: (mesh: MeshResource, bounds: BoundingBox)] = [:]

    private static func mesh(_ ch: Character) -> (mesh: MeshResource, bounds: BoundingBox) {
        if let g = glyphCache[ch] { return g }
        let m = MeshResource.generateText(String(ch), extrusionDepth: 0.24, font: font)
        let g = (m, m.bounds)
        glyphCache[ch] = g
        return g
    }

    private static func center(_ glyph: ModelEntity, on ch: Character, scale s: Float) {
        let b = mesh(ch).bounds
        glyph.position = -SIMD3<Float>((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2) * s
    }

    private static let face = material(Theme.paper, emissive: 1.0)
    private static let faceFlash = material(Theme.paper, emissive: 3.2)
    private static let side = material(Theme.gold, emissive: 0.9)
    private static let sideFlash = material(Theme.gold, emissive: 2.6)

    private static func materials(flash: Bool) -> [any RealityKit.Material] {
        flash ? [faceFlash, sideFlash] : [face, side]
    }

    private static func material(_ c: UIColor, emissive: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: 0.3)
        m.metallic = .init(floatLiteral: 0.15)
        m.emissiveColor = .init(color: c)
        m.emissiveIntensity = emissive
        return m
    }
}
