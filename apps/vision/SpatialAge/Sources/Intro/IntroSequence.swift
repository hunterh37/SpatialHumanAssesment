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

        // Title: 3.2 m out, a little above the eyes, facing the participant.
        let title = Self.title()
        let home = rig.world([0, rig.eye + 0.35, -3.2])
        title.position = home + [0, -0.6, 0]
        title.orientation = rig.rotation
        title.scale = .init(repeating: 0.001)
        layer.addChild(title)
        let glow = Self.halo()
        glow.position = [0, 0, -0.08]
        title.addChild(glow)

        Tone.play(.fanfare, on: title, gain: -10)
        clock.animate(1.6) { p in
            let k = Float(Ease.back(p))
            title.scale = .init(repeating: max(0.001, k))
            title.position = home + [0, -0.6 * (1 - Float(Ease.out(p))), 0]
        }
        // Each letter drops into place with a short stagger.
        for (i, letter) in title.children.filter({ $0.name.hasPrefix("letter") }).enumerated() {
            let rest = letter.position
            letter.position = rest + [0, 0.5, 0]
            let delay = 0.06 * Double(i)
            clock.animate(0.7 + delay) { p in
                let q = max(0, (p * (0.7 + delay) - delay) / 0.7)
                letter.position = rest + [0, 0.5 * (1 - Float(Ease.back(q))), 0]
            }
        }
        // Slow float and sway for the rest of the sequence.
        let sway = Task { @MainActor in
            var t: Double = 0
            while !Task.isCancelled {
                t += await clock.next()
                let s = Float(t)
                title.orientation = rig.rotation * simd_quatf(angle: 0.08 * sin(s * 0.5), axis: [0, 1, 0])
                if t > 1.6 { title.position = home + [0, 0.025 * sin(s * 0.9), 0] }
            }
        }
        defer { sway.cancel() }
        await clock.wait(3.2)
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
        let from = title.position
        clock.animate(1.0) { p in
            let k = Float(Ease.inOut(p))
            title.position = from + [0, 0.8 * k, -0.6 * k]
            title.scale = .init(repeating: max(0.001, 1 - k))
        }
        await clock.wait(1.1)
        bird.dismiss()
        title.removeFromParent()
        await clock.wait(0.6)
    }

    // MARK: Build

    /// BETTER YEARS as two lines of extruded rounded type, cream face with a peach rim, centered on the origin.
    static func title() -> Entity {
        let root = Entity()
        root.name = "introTitle"
        let face = material(Dusk.accent, emissive: 0.55)
        let rim = material(Dusk.accentStrong, emissive: 0.35)
        let lines: [(String, Float, Float)] = [("BETTER", 0.34, 0.2), ("YEARS", 0.34, -0.2)]
        var index = 0
        for (word, size, y) in lines {
            let font = roundedFont(size: CGFloat(size))
            // Measure the word so letters sit at their kerned offsets.
            let widths = word.map { ch -> Float in
                let w = (String(ch) as NSString).size(withAttributes: [.font: font]).width
                return Float(w)
            }
            let tracking: Float = 0.02
            let total = widths.reduce(0, +) + tracking * Float(max(0, widths.count - 1))
            var x = -total / 2
            for (k, ch) in word.enumerated() {
                let mesh = MeshResource.generateText(String(ch), extrusionDepth: 0.09, font: font,
                                                     containerFrame: .zero, alignment: .left, lineBreakMode: .byClipping)
                let letter = ModelEntity(mesh: mesh, materials: [face, rim])
                let b = mesh.bounds
                letter.name = "letter\(index)"
                letter.position = [x - b.min.x + (widths[k] - (b.max.x - b.min.x)) / 2, y - (b.min.y + b.max.y) / 2, -0.045]
                root.addChild(letter)
                x += widths[k] + tracking
                index += 1
            }
        }
        return root
    }

    /// Soft warm disc behind the title.
    static func halo() -> Entity {
        var m = UnlitMaterial(color: Dusk.accent.withAlphaComponent(0.12))
        m.blending = .transparent(opacity: .init(floatLiteral: 1))
        let disc = ModelEntity(mesh: .generatePlane(width: 3.4, height: 1.5, cornerRadius: 0.75), materials: [m])
        disc.name = "halo"
        return disc
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
