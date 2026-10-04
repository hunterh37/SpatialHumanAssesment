import RealKit
import ScoreKit
import SwiftUI

/// Main window. Consent, participant, catalog, running, results, then back to catalog or consent.
/// Opens the immersive space. `ImmersiveView` closes itself when the phase leaves `.running`.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var confirmStartOver = false

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .consent:
                VStack(spacing: 24) {
                    Text("Spatial Age").font(.largeTitle.weight(.semibold))
                    Text("Five short reach and memory games, about 7 minutes in full immersion. No names are stored. Not a medical test.")
                        .multilineTextAlignment(.center).frame(maxWidth: 520)
                    Button("I agree") { model.phase = .participant }
                        .buttonStyle(.borderedProminent)
                }
            case .participant:
                VStack(spacing: 20) {
                    Form {
                        TextField("Code", text: $model.participant.code)
                        Stepper("Age \(Int(model.participant.ageYears))", value: $model.participant.ageYears, in: 10...110)
                        Picker("Sex", selection: $model.participant.sex) {
                            ForEach(Participant.Sex.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        Picker("Handedness", selection: $model.participant.handedness) {
                            ForEach(Participant.Handedness.allCases, id: \.self) { Text($0.rawValue) }
                        }
                    }
                    HStack {
                        Button("Back") { model.phase = .consent }
                        Button("Continue") { model.phase = .catalog }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.participant.code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            case .catalog:
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button("Participant", systemImage: "chevron.left") { model.phase = .participant }
                        Spacer()
                        Text(model.participant.code).monospaced().foregroundStyle(.secondary)
                        Button("Start over") { confirmStartOver = true }
                    }
                    if let notice = model.notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    CatalogView { games in start(games) }
                }
            case .running:
                RunningView { model.abortSession() }
            case .results:
                ResultsView {
                    model.nextParticipant()
                } again: {
                    model.playAgain()
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) { AnatomyToggle().padding(.top, 20) }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .confirmationDialog("Start over with a new participant?", isPresented: $confirmStartOver) {
            Button("Start over", role: .destructive) { model.nextParticipant() }
        }
        .onAppear { model.windowOpen = true }
        #if DEBUG
        // Screenshot hook: SA_DEMO=<game> skips consent and runs that one game.
        .task {
            guard model.phase == .consent, let raw = ProcessInfo.processInfo.environment["SA_DEMO"],
                  let game = Game(rawValue: raw) else { return }
            start([game])
        }
        #endif
        .onDisappear { model.windowOpen = false }
        .onChange(of: model.spaceOpen) { _, open in
            // Space closed by the system or the Digital Crown mid-session.
            if !open, model.phase == .running { model.abortSession() }
        }
    }

    private func start(_ games: [Game]) {
        Task {
            if model.spaceOpen { await dismissImmersiveSpace() }
            model.start(games)
            model.passthrough = false
            switch await openImmersiveSpace(id: AppModel.immersiveID) {
            case .opened:
                // The window would sit in front of the stage. ImmersiveView reopens it when the session ends.
                if model.phase == .running { dismissWindow(id: AppModel.windowID) }
            case .userCancelled: model.abortSession("Immersion was cancelled.")
            case .error: model.abortSession("Could not open the immersive space.")
            @unknown default: model.abortSession("Could not open the immersive space.")
            }
        }
    }
}

/// Shown in the window while the games run. Also visible inside the full space.
struct RunningView: View {
    @Environment(AppModel.self) private var model
    let end: () -> Void
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Playing").font(.title)
            Text(model.queue.map(\.title).joined(separator: " · ")).foregroundStyle(.secondary)
            Button("End session", systemImage: "xmark", role: .destructive) { confirm = true }
                .padding(.top, 12)
        }
        .confirmationDialog("End the session? Progress is not saved.", isPresented: $confirm) {
            Button("End session", role: .destructive, action: end)
        }
    }
}

/// Main-window control for the hand anatomy overlay. Opens the immersive space in passthrough when
/// no game is running, and closes it again when the overlay is switched off.
struct AnatomyToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fingers.spread")
            Picker("Hand anatomy", selection: $model.anatomyMode) {
                Text("Off").tag(RealHandAnatomy.Mode.off)
                Text("X-ray").tag(RealHandAnatomy.Mode.xray)
                Text("Muscle").tag(RealHandAnatomy.Mode.muscle)
                Text("Both").tag(RealHandAnatomy.Mode.both)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .task {
            // Launch argument `-anatomy xray|muscle|both` opens the viewer directly (demos, captures).
            if let m = UserDefaults.standard.string(forKey: "anatomy").flatMap(RealHandAnatomy.Mode.init(rawValue:)), m != .off {
                model.anatomyMode = m
                await sync(m)
            }
        }
        .onChange(of: model.anatomyMode) { _, mode in Task { await sync(mode) } }
    }

    private func sync(_ mode: RealHandAnatomy.Mode) async {
        if mode != .off, !model.spaceOpen {
            model.passthrough = model.phase != .running
            model.spaceOpen = true
            if case .error = await openImmersiveSpace(id: AppModel.immersiveID) { model.spaceOpen = false }
        } else if mode == .off, model.spaceOpen, model.phase != .running {
            await dismissImmersiveSpace()
        }
    }
}
