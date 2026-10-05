import Observation
import RealityKit
import SwiftUI
import UIKit

/// State the intro card attachment reads. The sequence writes it; the card's button resumes the sequence.
@MainActor
@Observable
final class IntroCard {
    var visible = false
    var line = ""
    var button = ""
    /// World position of the card, set when Buddy lands.
    var anchor: SIMD3<Float>?
    @ObservationIgnored private var waiter: CheckedContinuation<Void, Never>?

    /// Shows the line and waits for the button (or cancellation).
    func ask(_ line: String, button: String) async {
        self.line = line
        self.button = button
        visible = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { @MainActor in self.answer() }
        }
        visible = false
    }

    func answer() {
        let w = waiter
        waiter = nil
        w?.resume()
    }
}

/// First-launch title sequence in the Dusk stage: BETTER YEARS rises as extruded 3D type in the brand
/// palette, Buddy the bird flies in and lands beside it, the card introduces him, and the participant
/// answers. The caller then opens setup.
@MainActor
struct IntroSequence {
    let clock: FrameClock
    let tracker: HandTracker
    let bird: Bird
    let layer: Entity
    let card: IntroCard

    static let line = "This is Buddy. He will be your guide through your better years."
    static let answer = "Nice to meet you, Buddy"

    func run() async {
        await clock.wait(0.8)
        var rig = Rig(head: matrix_identity_float4x4)
        rig.eye = 1.5
        if await tracker.waitForHead() { rig = Rig(head: tracker.head()) }

        // Title: 3 m (10 ft) capitals, 18 m out, centered on the gaze line, facing the participant.
        let title = Self.title()
        let home = rig.world([0, rig.eye + Self.lift, -Self.distance])
        title.position = home
        title.orientation = rig.rotation
        layer.addChild(title)

        // Each letter slides down from 16 m above into place, left to right, and lands with a small bounce.
        let letters = title.children.filter { $0.name.hasPrefix("letter") }
        let drop: Float = 16
        for (i, letter) in letters.enumerated() {
            let rest = letter.position
            letter.position = rest + [0, drop, 0]
            let delay = 0.09 * Double(i)
            let slide = 1.3
            clock.animate(slide + delay) { p in
                let q = max(0, (p * (slide + delay) - delay) / slide)
                letter.position = rest + [0, drop * (1 - Float(Ease.back(q))), 0]
            }
        }
        Tone.play(.fanfare, on: title, gain: -8)

        // Slow float and sway for the rest of the sequence.
        let sway = Task { @MainActor in
            var t: Double = 0
            while !Task.isCancelled {
                t += await clock.next()
                let s = Float(t)
                title.orientation = rig.rotation * simd_quatf(angle: 0.04 * sin(s * 0.4), axis: [0, 1, 0])
                title.position = home + [0, 0.12 * sin(s * 0.8), 0]
            }
        }
        defer { sway.cancel() }
        await clock.wait(0.09 * Double(letters.count) + 1.3 + 2.5)
        guard !Task.isCancelled else { return }

        // Buddy flies in and lands to the right of the card, at eye level.
        let perch = rig.world([0.42, rig.eye - 0.12, -1.25])
        bird.summon(to: perch)
        await clock.wait(3.0)
        guard !Task.isCancelled else { return }
        bird.sing()
        card.anchor = rig.world([-0.05, rig.eye - 0.05, -1.3])
        await card.ask(Self.line, button: Self.answer)
        guard !Task.isCancelled else { return }

        bird.sing()
        Tone.play(.sparkle, on: title, gain: -12)
        for (i, letter) in letters.enumerated() {
            let from = letter.position
            let delay = 0.05 * Double(i)
            clock.animate(1.0 + delay) { p in
                let q = max(0, (p * (1.0 + delay) - delay) / 1.0)
                letter.position = from + [0, -drop * Float(q * q), 0]
            }
        }
        await clock.wait(1.0 + 0.05 * Double(letters.count) + 0.1)
        bird.dismiss()
        title.removeFromParent()
        await clock.wait(0.6)
    }

    // MARK: Build

    /// Distance to the title and its center height above the eyes, meters.
    static let distance: Float = 18
    static let lift: Float = 3.4
    /// Capital height, meters (10 ft).
    static let capHeight: Float = 3.0

    /// BETTER YEARS as two lines of extruded rounded capitals, cream face, centered on the origin.
    /// Glyphs are built at 1 m font size and scaled, so tessellation stays sane at this size.
    static func title() -> Entity {
        let root = Entity()
        root.name = "introTitle"
        let face = material(Dusk.accent, emissive: 0.9)
        let side = material(Dusk.accentStrong, emissive: 0.6)
        let font = roundedFont(size: 1)
        let scale = capHeight / Float(font.capHeight)
        let gap: Float = 0.08 * scale
        let lineGap: Float = 0.9
        let rows = ["BETTER", "YEARS"]
        var index = 0
        for (r, word) in rows.enumerated() {
            let glyphs = word.map { ch -> (MeshResource, BoundingBox) in
                let m = MeshResource.generateText(String(ch), extrusionDepth: 0.22, font: font)
                return (m, m.bounds)
            }
            let widths = glyphs.map { ($0.1.max.x - $0.1.min.x) * scale }
            let total = widths.reduce(0, +) + gap * Float(max(0, widths.count - 1))
            // Row centers: BETTER above center, YEARS below.
            let y = (Float(rows.count - 1) / 2 - Float(r)) * (capHeight + lineGap)
            var x = -total / 2
            for (k, (mesh, b)) in glyphs.enumerated() {
                let letter = ModelEntity(mesh: mesh, materials: [face, side])
                letter.name = "letter\(index)"
                letter.scale = .init(repeating: scale)
                letter.position = [x - b.min.x * scale, y - (b.min.y + b.max.y) / 2 * scale, -(b.min.z + b.max.z) / 2 * scale]
                root.addChild(letter)
                x += widths[k] + gap
                index += 1
            }
        }
        return root
    }

    private static func material(_ c: UIColor, emissive: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: 0.45)
        m.metallic = .init(floatLiteral: 0.1)
        m.emissiveColor = .init(color: c)
        m.emissiveIntensity = emissive
        return m
    }

    private static func roundedFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}

/// Card next to Buddy: one line and one answer button, on strong Dusk glass.
struct IntroCardView: View {
    let card: IntroCard

    var body: some View {
        VStack(spacing: 22) {
            DuskLabel("Buddy")
            Text(card.line)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.duskInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(card.button) { card.answer() }
                .buttonStyle(.duskPrimaryLarge)
        }
        .padding(40)
        .frame(width: 620)
        .background(Color.duskGlassStrong, in: RoundedRectangle(cornerRadius: Dusk.Layout.windowRadius))
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: Dusk.Layout.windowRadius))
        .opacity(card.visible ? 1 : 0)
        .scaleEffect(card.visible ? 1 : 0.9)
        .animation(Dusk.Motion.spring, value: card.visible)
    }
}
