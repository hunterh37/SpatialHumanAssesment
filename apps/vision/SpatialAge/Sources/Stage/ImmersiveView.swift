import RealityKit
import ScoreKit
import SwiftUI

/// Fully immersive stage. Hosts the environment, the game layer and the HUD, and pumps the frame clock.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var model
    @State private var clock = FrameClock()
    @State private var hud = HUD()
    @State private var layer = Entity()
    @State private var updates: EventSubscription?

    var body: some View {
        RealityView { content, attachments in
            content.add(Stage.make())
            content.add(layer)
            if let panel = attachments.entity(for: "hud") {
                panel.position = [0, 1.75, -1.2]
                panel.components.set(BillboardComponent())
                content.add(panel)
            }
            updates = content.subscribe(to: SceneEvents.Update.self) { event in
                clock.tick(event.deltaTime)
            }
        } attachments: {
            Attachment(id: "hud") { HUDView(hud: hud) }
        }
        .upperLimbVisibility(.visible)
        .task { await play() }
    }

    @MainActor
    private func play() async {
        guard let recorder = model.recorder else { return }
        let tracker = HandTracker(clockStart: recorder.start)
        let tracking = Task { await tracker.run() }
        defer { tracking.cancel() }
        // Let tracking settle and the eyes adapt to the dark before the first stimulus.
        await clock.wait(1.5)
        let ctx = GameContext(clock: clock, tracker: tracker, recorder: recorder, layer: layer, hud: hud,
                              handedness: model.participant.handedness)
        await Director(ctx: ctx).run(model.queue)
        await model.finishSession()
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
        .opacity(hud.visible ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: hud.visible)
        .animation(.easeOut(duration: 0.2), value: hud.done)
    }
}
