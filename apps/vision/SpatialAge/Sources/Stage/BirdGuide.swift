import Observation
import RealityKit
import ScoreKit
import SwiftUI
import UIKit

/// State the speech bubble attachment reads. `BirdGuide` writes it; a tap on the bubble resumes the guide.
@MainActor
@Observable
final class SpeechBubble {
    var visible = false
    /// The whole line. The view lays it all out and shows the first `shown` characters, so the bubble
    /// keeps its size while the line types out.
    var text = ""
    var shown = 0
    var page = 0
    var pages = 0
    /// Call to action, shown once the line has typed out: "Tap to continue", "Tap to practice".
    var action = ""
    /// True on the last bubble before a block: the action starts the game.
    var starts = false
    /// World position of the bubble, set when the guide places Buddy.
    var anchor: SIMD3<Float>?

    var typed: Bool { shown >= text.count }

    @ObservationIgnored fileprivate var waiter: CheckedContinuation<Void, Never>?
    @ObservationIgnored fileprivate var finishTyping = false

    /// Bubble tapped. While the line is still typing, the first tap completes it; the next one continues.
    func tap() {
        guard visible else { return }
        if !typed {
            finishTyping = true
            return
        }
        let w = waiter
        waiter = nil
        w?.resume()
    }

    /// Releases a waiting guide without a tap (skip, exit, space closed).
    func release() {
        finishTyping = true
        let w = waiter
        waiter = nil
        w?.resume()
    }
}

/// Buddy explains each game before it starts. He flies in from wherever he is (always from in front),
/// lands on a twig that grows 1.2 m ahead and a little right of the participant, and talks in short
/// bubbles beside him. Each bubble types out at 55 characters per second with one soft syllable per word;
/// a tap completes the line, the next tap moves on, and the last tap starts the block. Then he flies off
/// and the countdown begins. Spec: specs/games/design.md, Guide.
@MainActor
final class BirdGuide {
    let bird: Bird
    let bubble: SpeechBubble
    let clock: FrameClock

    static let charsPerSecond = 55.0
    /// Longest wait for Buddy to land before the first bubble shows anyway, seconds.
    static let landTimeout = 4.0

    init(bird: Bird, bubble: SpeechBubble, clock: FrameClock) {
        self.bird = bird
        self.bubble = bubble
        self.clock = clock
    }

    /// Calls Buddy to his twig. Safe to call early (while a cheer plays) so he is down by the time
    /// `say` runs; a later call with the same rig keeps the same twig.
    func arrive(_ rig: Rig) {
        bird.attentive = true
        // Rig local: right of center, just below eye height, past arm's reach and under the HUD.
        bird.summon(to: rig.world([0.34, rig.eye - 0.13, -1.2]))
        // Bubble to Buddy's left at eye height, its tail pointing down-right at him.
        bubble.anchor = rig.world([-0.07, rig.eye + 0.01, -1.25])
    }

    /// Hides the bubble and sends Buddy off (game skipped or ended mid-explanation).
    func leave() {
        bubble.release()
        bubble.visible = false
        bird.dismiss()
    }

    /// Shows `lines` one bubble at a time and returns after the last tap, with Buddy on his way out.
    func say(_ lines: [String], action: String, rig: Rig) async {
        guard !lines.isEmpty else { return }
        arrive(rig)
        var waited = 0.0
        while !bird.perched, waited < Self.landTimeout, !Task.isCancelled { waited += await clock.next() }
        await clock.wait(0.2)

        for (i, line) in lines.enumerated() where !Task.isCancelled {
            let last = i == lines.count - 1
            bubble.text = line
            bubble.shown = 0
            bubble.page = i
            bubble.pages = lines.count
            bubble.action = last ? action : "Tap to continue"
            bubble.starts = last
            bubble.finishTyping = false
            bubble.visible = true
            if i == 0 { bird.sing() }
            await type(line)
            await waitForTap()
            guard !Task.isCancelled else { break }
            Tone.play(.bubble, on: bird.flight, gain: last ? -14 : -18)
        }
        bubble.visible = false
        bird.dismiss()
    }

    /// Types the line out, one syllable from Buddy at the start of each word. Reduce Motion shows it whole.
    private func type(_ line: String) async {
        let chars = Array(line)
        if UIAccessibility.isReduceMotionEnabled {
            bubble.shown = chars.count
            bird.talk(0)
            return
        }
        var t = 0.0
        var word = 0
        while bubble.shown < chars.count, !Task.isCancelled {
            if bubble.finishTyping {
                bubble.shown = chars.count
                break
            }
            t += await clock.next()
            let next = min(chars.count, Int(t * Self.charsPerSecond))
            for k in bubble.shown..<max(next, bubble.shown) where k == 0 || (chars[k - 1] == " " && chars[k] != " ") {
                bird.talk(word)
                word += 1
            }
            if next > bubble.shown { bubble.shown = next }
        }
    }

    private func waitForTap() async {
        guard !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { bubble.waiter = $0 }
        } onCancel: {
            Task { @MainActor in self.bubble.release() }
        }
    }
}

// MARK: - Copy

extension Game {
    /// Buddy's explanation before the first block, one string per bubble. Each bubble is one idea in
    /// plain words, short enough to read in about two seconds. Matches the HUD instruction in `Game.swift`.
    var guideLines: [String] {
        switch self {
        case .pendulum: ["Leaves hang from the branch in front of you.", "When one falls, catch it before it hits the ground!"]
        case .spark: ["Listen for a rustle and watch for a glow. Some come from behind you.", "Point at each falling leaf before it lands."]
        case .gate: ["Blue and orange lights will pop up.", "Touch blue as fast as you can. Leave orange alone."]
        case .constellation: ["Stars will light up one by one.", "Then touch them back in the same order."]
        case .orbit: ["Rest your fingertip in the teal light.", "When it moves, keep your finger inside it."]
        case .reach: ["Walk to the glowing spot, then reach for the cube.", "If a creature drifts by, freeze until it passes!"]
        case .wall: ["Stay on your island. A wall is coming.", "Put your hands in the blue rings and hold the shape."]
        case .dots: ["Touch only the balls the sign asks for.", "Then they turn grey. Find the ones you touched, or the ones you didn't."]
        }
    }

    /// Buddy's one bubble between the practice and the scored block.
    var guideAgain: String {
        isTimed ? "Nice practice! Now it counts. Be quick." : "Nice practice! Now it counts. Same as before."
    }
}

// MARK: - View

/// Buddy's speech bubble: strong Dusk glass with a tail toward him, the typed line, page dots and the
/// call to action. The whole bubble is one button, so a look and a pinch anywhere on it continues.
struct SpeechBubbleView: View {
    let bubble: SpeechBubble
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 560

    var body: some View {
        let shape = BubbleShape()
        Button { bubble.tap() } label: {
            VStack(alignment: .leading, spacing: 16) {
                DuskLabel("Buddy")
                typedLine
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    if bubble.pages > 1 { DuskDots(total: bubble.pages, done: bubble.page, size: 7) }
                    Spacer(minLength: 8)
                    action
                }
                .frame(height: 40)
            }
            .padding(.leading, 34)
            .padding(.trailing, 34 + BubbleShape.tail)
            .padding(.vertical, 28)
            .frame(width: Self.width + BubbleShape.tail)
            .background(Color.duskGlassStrong, in: shape)
            .glassBackgroundEffect(in: shape)
            .overlay { DuskEdge(shape: shape) }
            .contentShape(.hoverEffect, shape)
            .contentShape(shape)
        }
        .buttonStyle(BubblePress())
        .hoverEffect(.highlight)
        .accessibilityLabel(bubble.text)
        .accessibilityHint(bubble.action)
        // A new bubble springs a little; the first one grows out of the tail.
        .keyframeAnimator(initialValue: CGFloat(1), trigger: bubble.page) { view, s in
            view.scaleEffect(reduceMotion ? 1 : s, anchor: .bottomTrailing)
        } keyframes: { _ in
            SpringKeyframe(1.04, duration: 0.1, spring: .snappy)
            SpringKeyframe(1, duration: 0.25, spring: .smooth)
        }
        .scaleEffect(bubble.visible || reduceMotion ? 1 : 0.55, anchor: .bottomTrailing)
        .opacity(bubble.visible ? 1 : 0)
        .allowsHitTesting(bubble.visible)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.32), value: bubble.visible)
    }

    /// Typed part in ink, the rest laid out but clear, so lines never re-wrap as they type.
    private var typedLine: Text {
        let chars = Array(bubble.text)
        let n = min(max(bubble.shown, 0), chars.count)
        return Text(String(chars[..<n])).foregroundStyle(Color.duskInk)
            + Text(String(chars[n...])).foregroundStyle(Color.clear)
    }

    /// "Tap to continue" with a chevron, or the start action with a play glyph. Appears once the line is typed.
    private var action: some View {
        HStack(spacing: 8) {
            Text(bubble.action)
            Image(systemName: bubble.starts ? "play.fill" : "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .phaseAnimator([0, 1]) { glyph, phase in
                    glyph.offset(x: reduceMotion || !bubble.typed ? 0 : phase * 4)
                } animation: { _ in .easeInOut(duration: 0.55) }
        }
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .foregroundStyle(bubble.starts ? Color(uiColor: Dusk.onAccent) : Color.duskInk)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(bubble.starts ? Color(uiColor: Dusk.accent) : Color.duskChipStrong, in: Capsule())
        .opacity(bubble.typed ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: bubble.typed)
    }
}

/// Rounded body with a curved tail off the lower right edge. The tail sits in the last `tail` points of
/// the frame, so it is never clipped.
struct BubbleShape: InsettableShape {
    static let tail: CGFloat = 34
    static let radius: CGFloat = 34
    var inset: CGFloat = 0

    /// One outline, clockwise from the top left, so the edge stroke runs around body and tail as one.
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let right = r.maxX - Self.tail
        let rad = min(Self.radius, r.height / 2, (right - r.minX) / 2)
        let tailTop = r.maxY - rad - 30
        let tailBase = r.maxY - rad
        let tip = CGPoint(x: r.maxX, y: r.maxY - 4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + rad, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: right, y: r.minY), tangent2End: CGPoint(x: right, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: right, y: tailTop))
        // Tail: bulges out, curls down to the point, and tucks back into the edge above the corner.
        p.addQuadCurve(to: tip, control: CGPoint(x: right + Self.tail * 0.3, y: tailTop + 22))
        p.addQuadCurve(to: CGPoint(x: right, y: tailBase), control: CGPoint(x: right + Self.tail * 0.15, y: tip.y - 6))
        p.addArc(tangent1End: CGPoint(x: right, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: right, y: r.minY), radius: rad)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> BubbleShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// Press feedback for the bubble: a quick squash toward the tail.
private struct BubblePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1, anchor: .bottomTrailing)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: configuration.isPressed)
    }
}
