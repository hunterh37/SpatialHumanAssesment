import SwiftUI

@main
struct SpatialAgeApp: App {
    @State private var model = AppModel()
    @State private var immersion: ImmersionStyle = .full

    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
        }
        .defaultSize(width: 980, height: 640)

        ImmersiveSpace(id: AppModel.immersiveID) {
            ImmersiveView().environment(model)
        }
        .immersionStyle(selection: $immersion, in: .full)
    }
}
