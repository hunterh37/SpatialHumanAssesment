import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 24) {
            switch model.phase {
            case .consent:
                Text("Spatial Age").font(.largeTitle)
                Text("About 6 minutes of reach and memory tasks. No names are stored. Not a medical test.")
                    .multilineTextAlignment(.center)
                Button("I agree") { model.phase = .participant }
            case .participant:
                Form {
                    LabeledContent("Code", value: model.participant.code)
                    Stepper("Age \(model.participant.ageYears)", value: $model.participant.ageYears, in: 10...110)
                    Picker("Sex", selection: $model.participant.sex) {
                        ForEach(Participant.Sex.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    Picker("Handedness", selection: $model.participant.handedness) {
                        ForEach(Participant.Handedness.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
                Button("Start") {
                    model.startSession()
                    Task { await openImmersiveSpace(id: AppModel.immersiveID) }
                }
            case .running:
                Text("Session running").font(.title)
            case .results:
                Text(model.lastResult ?? "-").font(.body.monospaced())
                Button("Next participant") {
                    Task { await dismissImmersiveSpace() }
                    model.participant = Participant(code: Participant.randomCode(), ageYears: 30, sex: .unspecified, handedness: .right)
                    model.phase = .consent
                }
            }
        }
        .padding(40)
    }
}
