import SwiftUI

@main
struct SpatialAgeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: AppModel.windowID) {
            ContentView().environment(model)
                #if DEBUG
                .modifier(BirdPreviewLaunch(model: model))
                #endif
        }
        // Dusk glass is drawn by the views (46 pt corners, charcoal tint, edge); the window bar stays the system one.
        .windowStyle(.plain)
        .defaultSize(width: 1240, height: 800)

        ImmersiveSpace(id: AppModel.immersiveID) {
            ImmersiveView().environment(model)
        }
        .immersionStyle(selection: Binding<any ImmersionStyle>(
            get: { model.passthrough ? .mixed : .full },
            set: { model.passthrough = $0 is MixedImmersionStyle }
        ), in: .mixed, .full)
    }
}

#if DEBUG
/// Launch argument `-birdpreview YES` opens the stage with the bird perched in front, for captures.
private struct BirdPreviewLaunch: ViewModifier {
    let model: AppModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    func body(content: Content) -> some View {
        content.task {
            guard UserDefaults.standard.bool(forKey: "birdpreview"), !model.spaceOpen else { return }
            model.passthrough = false
            model.spaceOpen = true
            if case .opened = await openImmersiveSpace(id: AppModel.immersiveID) {} else { model.spaceOpen = false }
        }
    }
}
#endif
