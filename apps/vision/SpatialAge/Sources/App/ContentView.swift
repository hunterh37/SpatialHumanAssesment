import ScoreKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

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
                    Button("Continue") { model.phase = .catalog }
                }
            case .catalog:
                CatalogView { games in
                    model.start(games)
                    Task { await openImmersiveSpace(id: AppModel.immersiveID) }
                }
            case .running:
                VStack(spacing: 12) {
                    Text("Playing").font(.title)
                    Text(model.queue.map(\.title).joined(separator: " · ")).foregroundStyle(.secondary)
                }
            case .results:
                ResultsView {
                    Task { await dismissImmersiveSpace() }
                    model.nextParticipant()
                } again: {
                    Task { await dismissImmersiveSpace() }
                    model.phase = .catalog
                }
            }
        }
        .padding(40)
        .onChange(of: model.phase) { _, phase in
            if phase == .results { Task { await dismissImmersiveSpace() } }
        }
    }
}
