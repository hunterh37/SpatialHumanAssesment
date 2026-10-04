import SwiftUI

@main
struct SpatialAgeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
        }
        .defaultSize(width: 980, height: 640)

        ImmersiveSpace(id: AppModel.immersiveID) {
            ImmersiveView().environment(model)
        }
        .immersionStyle(selection: Binding<any ImmersionStyle>(
            get: { model.passthrough ? .mixed : .full },
            set: { model.passthrough = $0 is MixedImmersionStyle }
        ), in: .mixed, .full)
    }
}
