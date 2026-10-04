import QuartzCore
import RealityKit
import ScoreKit
import SwiftUI

/// Fully immersive stage. Hosts the environment, the game layer and the HUD, and pumps the frame clock.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var clock = FrameClock()
    @State private var hud = HUD()
    @State private var layer = Entity()
    @State private var stage = Entity()
    @State private var anatomy = AnatomyOverlay()
    @State private var plank = SkyPlank()
    /// Built once in the RealityView make closure; a `@State` default would rebuild the rig on every view init.
    @State private var bird: Bird?
    @State private var tracker: HandTracker?
    @State private var updates: EventSubscription?
    @State private var game: Task<Void, Never>?
    @State private var closing = false
    @State private var introCard = IntroCard()
    @State private var bubble = SpeechBubble()
    /// True once this space started the intro sequence, so only its own close ends the intro.
    @State private var introActive = false

    var body: some View {
        RealityView { content, attachments in
            let s = Stage.make()
            stage.addChild(s)
            let bird = self.bird ?? Bird()
            self.bird = bird
            stage.addChild(bird.root)
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "birdpreview") { bird.preview(at: [0.36, 1.42, -0.55]) }
            #endif
            content.add(stage)
            content.add(layer)
            content.add(plank.root)
            content.add(anatomy.root)
            // HUD and exit sit low, past arm's reach. GameContext moves them in front of the participant
            // at each game start (hud.anchor); until then they wait at a seated default.
            let panel = attachments.entity(for: "hud")
            if let panel {
                panel.position = [0, 0.7, -Theme.Layout.distance]
                panel.components.set(BillboardComponent())
                content.add(panel)
            }
            if let card = attachments.entity(for: "intro") {
                card.position = [0, 1.4, -1.3]
                card.components.set(BillboardComponent())
                content.add(card)
            }
            let introEntity = attachments.entity(for: "intro")
            let bubbleEntity = attachments.entity(for: "bubble")
            if let bubbleEntity {
                bubbleEntity.position = [0, 1.5, -1.25]
                bubbleEntity.components.set(BillboardComponent())
                content.add(bubbleEntity)
            }
            let exit = attachments.entity(for: "exit")
            if let exit {
                exit.position = [0, 0.4, -Theme.Layout.distance]
                exit.components.set(BillboardComponent())
                content.add(exit)
            }
            updates = content.subscribe(to: SceneEvents.Update.self) { event in
                if let a = hud.anchor, panel?.position != a { panel?.position = a }
                if let a = hud.exitAnchor, exit?.position != a { exit?.position = a }
                if let a = introCard.anchor, introEntity?.position != a { introEntity?.position = a }
                if let a = bubble.anchor, bubbleEntity?.position != a { bubbleEntity?.position = a }
                clock.tick(event.deltaTime)
                Stage.tick(stage, dt: event.deltaTime, ambient: hud.ambient)
                if stage.isEnabled { bird.update(dt: event.deltaTime, tracker: tracker, ambient: hud.ambient) }
                anatomy.update(tracker: tracker, dt: event.deltaTime)
            }
        } attachments: {
            Attachment(id: "hud") { HUDView(hud: hud) }
            Attachment(id: "intro") { IntroCardView(card: introCard) }
            Attachment(id: "bubble") { SpeechBubbleView(bubble: bubble) }
            Attachment(id: "exit") {
                if model.phase == .running { ExitControl { model.abortSession() } }
                else if model.skyPlank { ExitControl(title: "Leave the roof") { model.skyPlank = false } }
            }
        }
        // Real hands cover virtual content; hide them while the anatomy overlay replaces them.
        .upperLimbVisibility(model.anatomyMode == .off ? .visible : .hidden)
        .onChange(of: model.anatomyMode, initial: true) { _, m in anatomy.setMode(m) }
        .onChange(of: model.passthrough, initial: true) { _, mixed in stage.isEnabled = !mixed && !model.skyPlank }
        .onChange(of: model.skyPlank, initial: true) { was, on in Task { await syncPlank(on, was: was) } }
        .onAppear { model.spaceOpen = true }
        .onDisappear {
            halt()
            // Closed by the Digital Crown or the system mid-session: end it and bring the window back.
            if model.phase == .running { model.abortSession() }
            if introActive, model.phase == .intro { model.finishIntro() }
            showWindow()
            updates?.cancel()
            updates = nil
            model.spaceOpen = false
        }
        .onChange(of: model.phase) { _, phase in
            // Session ended (finished, aborted or reset): stop the games and clear the scene.
            // With the anatomy overlay on, stay open in passthrough; otherwise close the space.
            // Replaying the intro: ContentView closes this space and opens a fresh one for the sequence.
            guard phase != .running, phase != .intro else { return }
            halt()
            showWindow()
            if model.skyPlank { return }
            if model.anatomyMode == .off { close() } else { model.passthrough = true }
        }
        .task { await anatomy.prepare() }
        .task { await run() }
    }

    @MainActor
    private func run() async {
        let recorder = model.phase == .running ? model.recorder : nil
        let t = HandTracker(clockStart: recorder?.start ?? CACurrentMediaTime())
        tracker = t
        let tracking = Task { await t.run() }
        defer {
            tracking.cancel()
            t.stop()
        }
        if let recorder {
            let g = Task { await play(recorder, t) }
            game = g
            await g.value
        } else if model.phase == .intro {
            // The RealityView make closure builds the bird; this task can start before it finishes.
            while bird == nil, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
            guard let bird else { return }
            introActive = true
            model.introRunning = true
            let g = Task { @MainActor in
                await IntroSequence(clock: clock, tracker: t, bird: bird, layer: layer, card: introCard).run()
            }
            game = g
            await g.value
            if !Task.isCancelled { model.finishIntro() }
        }
        // Anatomy viewer, or a finished session with the overlay on: keep tracking until the space closes.
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
    }

    private func play(_ recorder: SessionRecorder, _ t: HandTracker) async {
        // Let tracking settle and the eyes adapt to the dark before the first stimulus.
        await clock.wait(1.5)
        let ctx = GameContext(clock: clock, tracker: t, recorder: recorder, layer: layer, hud: hud,
                              handedness: model.participant.handedness)
        if let bird, stage.isEnabled { ctx.guide = BirdGuide(bird: bird, bubble: bubble, clock: clock) }
        await Director(ctx: ctx, practice: model.practiceFirst).run(model.queue)
        // Ended early: the window already shows the catalog. Do not score a partial run.
        guard !Task.isCancelled, model.phase == .running else { return }
        await model.finishSession()
    }

    /// Cancels the game task, releases frame waiters and removes every game entity and the HUD.
    private func halt() {
        game?.cancel()
        game = nil
        clock.stop()
        hud.visible = false
        introCard.answer()
        introCard.visible = false
        bubble.release()
        bubble.visible = false
        bird?.dismiss()
        layer.children.removeAll()
    }

    /// Shows the rooftop with the board start under the participant, facing where they face; hides it
    /// and closes the space (or drops to passthrough for the anatomy overlay) when switched off.
    private func syncPlank(_ on: Bool, was: Bool) async {
        if on {
            stage.isEnabled = false
            // The hand tracker starts with the space; give it a moment so the board lands under the feet.
            for _ in 0..<40 where tracker == nil { try? await Task.sleep(for: .milliseconds(50)) }
            var rig = Rig(head: matrix_identity_float4x4)
            if let tracker, await tracker.waitForHead() { rig = Rig(head: tracker.head()) }
            let d = Theme.Layout.distance
            hud.exitAnchor = rig.world([0, rig.eye - Theme.Layout.exitDrop, -d])
            await plank.show(at: rig)
        } else {
            plank.hide()
            stage.isEnabled = !model.passthrough
            guard was, model.spaceOpen, model.phase != .running else { return }
            if model.anatomyMode == .off { close() } else { model.passthrough = true }
        }
    }

    /// Reopens the main window, which was dismissed while the games ran.
    private func showWindow() {
        if !model.windowOpen { openWindow(id: AppModel.windowID) }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        Task { await dismissImmersiveSpace() }
    }
}

/// In-play HUD (Dusk spec section 7): a small glass capsule at the top with the game title, one
/// instruction line, progress dots and skip. Below it a cue line (countdown, short praise). No scores.
struct HUDView: View {
    let hud: HUD
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    DuskLabel(hud.title)
                    Text(hud.line)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Color.duskInk)
                        .lineLimit(3)  // the longer deck instructions plus "Practice. " need a third line
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                DuskDots(total: hud.total, done: hud.done, size: 7)
                if hud.skip != nil {
                    Button {
                        if armed { hud.skip?(); armed = false } else { arm() }
                    } label: {
                        Label(armed ? "Tap again to skip this game" : "Skip this game", systemImage: "xmark")
                    }
                    .buttonStyle(.duskIcon)
                    .help(armed ? "Tap again to skip" : "Skip this game")
                    .overlay(alignment: .bottom) {
                        if armed {
                            Text("Tap again").font(.caption.weight(.semibold)).foregroundStyle(Color.duskInk)
                                .fixedSize().offset(y: 26)
                        }
                    }
                }
            }
            .padding(.leading, 32).padding(.trailing, 14).padding(.vertical, 14)
            .frame(width: 860)
            .background(Color.duskGlassStrong, in: Capsule())
            .glassBackgroundEffect(in: Capsule())
            .overlay { DuskEdge(shape: Capsule()) }

            Text(hud.cue)
                .font(DuskType.hero(56))
                .foregroundStyle(Color.duskInk)
                .shadow(color: .duskShadow, radius: 8)
                .shadow(color: Color(Theme.gold).opacity(hud.cue.isEmpty ? 0 : 0.55), radius: 18)
                .frame(height: 66)
                .contentTransition(.numericText())
                // Each new cue springs in: 1 to 1.22 and back with a small overshoot. Off under Reduce Motion.
                .keyframeAnimator(initialValue: CGFloat(1), trigger: hud.cue) { view, scale in
                    view.scaleEffect(reduceMotion ? 1 : scale)
                } keyframes: { _ in
                    SpringKeyframe(1.22, duration: 0.12, spring: .snappy)
                    SpringKeyframe(0.96, duration: 0.12, spring: .smooth)
                    SpringKeyframe(1, duration: 0.18, spring: .smooth)
                }
        }
        .opacity(hud.visible ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: hud.visible)
        .animation(.easeOut(duration: 0.2), value: hud.done)
        .animation(.easeOut(duration: 0.15), value: hud.cue)
        .animation(Dusk.Motion.quick, value: armed)
    }

    private func arm() {
        armed = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            armed = false
        }
    }
}

/// Exit button inside the full space. First tap arms it, second tap within 3 s ends the session,
/// so a stray reach during a trial cannot end it. Secondary capsule on strong glass.
struct ExitControl: View {
    var title = "End session"
    let exit: () -> Void
    @State private var armed = false

    var body: some View {
        Button {
            if armed { exit() } else { arm() }
        } label: {
            Label(armed ? "Tap again to end" : title, systemImage: "xmark")
        }
        .buttonStyle(.duskSecondary)
        .background(Color.duskGlassStrong, in: Capsule())
        .glassBackgroundEffect(in: Capsule())
        .animation(Dusk.Motion.quick, value: armed)
    }

    private func arm() {
        armed = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            armed = false
        }
    }
}
