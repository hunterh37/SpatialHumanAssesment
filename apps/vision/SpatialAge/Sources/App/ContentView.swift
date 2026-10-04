import RealKit
import ScoreKit
import SwiftUI

/// Main window. First-run setup (consent and player stats), then Home / Games / Progress / Duel under the leading tab ornament,
/// running, results. Opens the immersive space. `ImmersiveView` closes itself when the phase leaves `.running`.
/// Dusk spec sections 4 to 7: charcoal glass, cream type, one primary action per screen.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .onboarding:
                if model.editingSetup, let p = model.profile {
                    OnboardingView(start: .review, draft: OnboardingDraft(p))
                } else {
                    OnboardingView()
                }
            case .catalog:
                TabView(selection: $model.tab) {
                    Tab("Home", systemImage: "house", value: AppModel.Tab.home) { screen { HomeView() } }
                    Tab("Games", systemImage: "square.grid.2x2", value: AppModel.Tab.games) {
                        screen { GamesView(start: start) }
                    }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppModel.Tab.progress) {
                        screen { ProgressTab() }
                    }
                    Tab("Duel", systemImage: "person.2", value: AppModel.Tab.duel) { screen { DuelView(start: start) } }
                }
                .tint(Color.duskAccent)
            case .running: screen { RunningView { model.abortSession() } }
            case .results:
                screen {
                    ResultsView {
                        model.nextParticipant()
                    } again: {
                        model.playAgain()
                    }
                }
            }
        }
        .foregroundStyle(Color.duskInk)
        .tint(Color.duskAccentStrong)
        .preferredColorScheme(.dark)
        .animation(Dusk.Motion.spring, value: model.phase)
        .onAppear { model.windowOpen = true }
        #if DEBUG
        // Screenshot hook: SA_DEMO=<game> skips setup and runs that one game.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["SA_DEMO"],
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

    /// One glass window surface per screen: 46 pt corners, charcoal tint, edge and highlight.
    private func screen(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .duskGlass()
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

/// Age in whole years: minus and plus icon buttons around a tabular number.
struct AgeStepper: View {
    @Binding var age: Double
    var range: ClosedRange<Double> = 10...110

    var body: some View {
        HStack(spacing: 16) {
            Button("Younger", systemImage: "minus") { age = max(range.lowerBound, age - 1) }
                .buttonStyle(.duskIcon)
                .disabled(age <= range.lowerBound)
            Text("\(Int(age))").font(.title2.weight(.light)).monospacedDigit().frame(minWidth: 52)
            Button("Older", systemImage: "plus") { age = min(range.upperBound, age + 1) }
                .buttonStyle(.duskIcon)
                .disabled(age >= range.upperBound)
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmStartOver = false
    @State private var history: [ScoreReport] = []

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(spacing: 20) {
                DuskLabel(DuskCopy.brand)
                Text(DuskCopy.homeTitle).font(DuskType.title).multilineTextAlignment(.center)
                Text(DuskCopy.homeLine)
                    .duskSecondary()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                VStack(spacing: Dusk.Layout.spacing) {
                    Button("Start a duel") { model.tab = .duel }.buttonStyle(.duskPrimaryLarge)
                    Button("Play one game") { model.tab = .games }.buttonStyle(.duskSecondaryLarge)
                }
                .padding(.top, 12)
                if let notice = model.notice { DuskChip(text: notice) }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: Dusk.Layout.spacing) {
                lastAgeCard
                MusicMiniPlayer()
                viewersCard
                HStack {
                    Button("Edit setup") { model.editSetup() }.buttonStyle(.duskTertiary)
                    Spacer()
                    Button("Start over") { confirmStartOver = true }.buttonStyle(.duskTertiary)
                }
            }
            .frame(width: 330)
        }
        .confirmationDialog("Start over with a new participant?", isPresented: $confirmStartOver) {
            Button("Start over", role: .destructive) { model.nextParticipant() }
        }
        .task(id: model.participant.code) { history = model.history() }
    }

    private var lastAgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DuskLabel("Last movement age")
                Spacer()
                Text(model.participant.code).font(DuskType.data.monospaced()).duskSecondary()
            }
            if let last = history.last?.spatialAge {
                Text(String(format: "%.1f", last)).font(DuskType.hero(64))
                if history.count > 1, let first = history.first?.spatialAge {
                    let delta = last - first
                    DuskChip(text: String(format: "%+.1f years since first visit", delta),
                             kind: delta < 0 ? .improved : .neutral)
                }
            } else {
                Text("–").font(DuskType.hero(64))
                Text("Play a game to see it here.").font(.callout).duskSecondary()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duskCard()
    }

    private var viewersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DuskLabel("Viewers")
            AnatomyToggle()
            SkyPlankToggle()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duskCard()
    }
}

// MARK: - Running

/// Shown in the window while the games run. The window normally hides during play.
struct RunningView: View {
    @Environment(AppModel.self) private var model
    let end: () -> Void
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 18) {
            DuskLabel("Playing")
            Text(model.queue.map(\.duskTitle).joined(separator: " · "))
                .font(DuskType.screenTitle).multilineTextAlignment(.center)
            Button("End session", systemImage: "xmark") { confirm = true }
                .buttonStyle(.duskSecondary)
                .padding(.top, 12)
        }
        .confirmationDialog("End the session? Progress is not saved.", isPresented: $confirm) {
            Button("End session", role: .destructive, action: end)
        }
    }
}

// MARK: - Viewers

/// Hand anatomy overlay control. Opens the immersive space in passthrough when no game is running,
/// and closes it again when the overlay is switched off.
struct AnatomyToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            Label("Hand anatomy", systemImage: "hand.raised.fingers.spread").font(.callout).duskSecondary()
            DuskSegmented(selection: $model.anatomyMode, options: [
                (RealHandAnatomy.Mode.off, "Off"), (.xray, "X-ray"), (.muscle, "Muscle"), (.both, "Both"),
            ])
        }
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

/// Sky Plank height viewer switch. Opens the space in full immersion (or lifts an open passthrough
/// space to full); switching off closes it via ImmersiveView.
struct SkyPlankToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        @Bindable var model = model
        Toggle(isOn: $model.skyPlank) {
            Label("Sky Plank", systemImage: "building.2")
        }
        .toggleStyle(DuskToggleStyle())
        .disabled(model.phase == .running)
        .task {
            // Launch argument `-skyplank YES` opens the viewer directly (demos, captures).
            if UserDefaults.standard.bool(forKey: "skyplank") { model.skyPlank = true }
        }
        .onChange(of: model.skyPlank) { _, on in
            guard on else { return }
            model.passthrough = false
            guard !model.spaceOpen else { return }
            model.spaceOpen = true
            Task {
                switch await openImmersiveSpace(id: AppModel.immersiveID) {
                case .opened: break
                default:
                    model.spaceOpen = false
                    model.skyPlank = false
                }
            }
        }
    }
}
