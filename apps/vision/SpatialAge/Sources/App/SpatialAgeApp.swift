import SwiftUI

@main
struct SpatialAgeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
        }
        .defaultSize(width: 600, height: 500)

        ImmersiveSpace(id: AppModel.immersiveID) {
            TaskRunnerView().environment(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
