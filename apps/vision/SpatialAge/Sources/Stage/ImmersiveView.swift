import QuartzCore
import RealityKit
import ScoreKit
import SwiftUI

/// Fully immersive stage. Hosts the environment, the game layer and the HUD, and pumps the frame clock.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var clock = FrameClock()
    @State private var hud = HUD()
    @State private var layer = Entity()
    @State private var stage = Entity()
    @State private var anatomy = AnatomyOverlay()
    @State private var tracker: HandTracker?
    @State private var updates: EventSubscription?
    @State private var game: Task<Void, Never>?
    @State private var closing = false

    var body: some View {
        RealityView { content, attachments in
            let s = Stage.make()
            stage.addChild(s)
            content.add(stage)
            content.add(layer)
            content.add(anatomy.root)
            if let panel = attachments.entity(for: "hud") {
                panel.position = [0, 1.75, -1.2]
                panel.components.set(BillboardComponent())
                content.add(panel)
            }
            if let exit = attachments.entity(for: "exit") {
                // Low and close, below the play area, so a reach never hits it by accident.
                exit.position = [0, 0.95, -0.75]
                exit.components.set(BillboardComponent())
                content.add(exit)
            }
            updates = content.subscribe(to: SceneEvents.Update.self) { event in
                clock.tick(event.deltaTime)
                anatomy.update(tracker: tracker, dt: event.deltaTime)
            }
        } attachments: {
            Attachment(id: "hud") { HUDView(hud: hud) }
            Attachment(id: "exit") {
                if model.phase == .running { ExitControl { model.abortSession() } }
            }
        }
        // Real hands cover virtual content; hide them while the anatomy overlay replaces them.
        .upperLimbVisibility(model.anatomyMode == .off ? .visible : .hidden)
        .onChange(of: model.anatomyMode, initial: true) { _, m in anatomy.setMode(m) }
        .onChange(of: model.passthrough, initial: true) { _, mixed in stage.isEnabled = !mixed }
        .onAppear { model.spaceOpen = true }
        .onDisappear {
            halt()
            updates?.cancel()
            updates = nil
            model.spaceOpen = false
        }
        .onChange(of: model.phase) { _, phase in
            // Session ended (finished, aborted or reset): stop the games and clear the scene.
            // With the anatomy overlay on, stay open in passthrough; otherwise close the space.
            guard phase != .running else { return }
            halt()
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
        }
        // Anatomy viewer, or a finished session with the overlay on: keep tracking until the space closes.
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
    }

    private func play(_ recorder: SessionRecorder, _ t: HandTracker) async {
        // Let tracking settle and the eyes adapt to the dark before the first stimulus.
        await clock.wait(1.5)
        let ctx = GameContext(clock: clock, tracker: t, recorder: recorder, layer: layer, hud: hud,
                              handedness: model.participant.handedness)
        await Director(ctx: ctx).run(model.queue)
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
        layer.children.removeAll()
    }

    private func close() {
        guard !closing else { return }
        closing = true
        Task { await dismissImmersiveSpace() }
    }
}

/// Title, one instruction line and progress dots. No numbers during play.
struct HUDView: View {
    let hud: HUD

    var body: some View {
        VStack(spacing: 10) {
            Text(hud.title.uppercased())
                .font(.system(size: 13, weight: .semibold)).tracking(3)
                .foregroundStyle(Theme.color(Theme.mute))
            Text(hud.line)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.color(Theme.paper))
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach(0..<max(hud.total, 0), id: \.self) { i in
                    Circle()
                        .fill(Theme.color(i < hud.done ? Theme.paper : Theme.mute).opacity(i < hud.done ? 1 : 0.35))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(width: 560)
        .overlay(alignment: .topTrailing) {
            if !hud.step.isEmpty {
                Text(hud.step).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.color(Theme.mute))
            }
        }
        .opacity(hud.visible ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: hud.visible)
        .animation(.easeOut(duration: 0.2), value: hud.done)
    }
}

/// Exit button inside the full space. First tap arms it, second tap within 3 s ends the session,
/// so a stray reach during a trial cannot end it.
struct ExitControl: View {
    let exit: () -> Void
    @State private var armed = false

    var body: some View {
        Button {
            if armed { exit() } else { arm() }
        } label: {
            Label(armed ? "Tap again to end" : "End session", systemImage: "xmark")
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 6)
        }
        .tint(armed ? Theme.color(Theme.nogo) : nil)
        .glassBackgroundEffect()
        .animation(.easeOut(duration: 0.2), value: armed)
    }

    private func arm() {
        armed = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            armed = false
        }
    }
}
