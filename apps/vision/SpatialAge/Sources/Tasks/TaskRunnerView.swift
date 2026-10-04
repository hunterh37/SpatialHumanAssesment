import RealityKit
import SwiftUI

/// Runs simple RT, choice RT, then Corsi. Specs: specs/tasks/*.md.
/// TODO(owner-vision): implement each task as its own type conforming to `AssessmentTask`.
struct TaskRunnerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        RealityView { content in
            let target = ModelEntity(mesh: .generateSphere(radius: 0.06),
                                     materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
            target.position = [0, 1.3, -0.5]
            content.add(target)
        }
        .task {
            // Placeholder until tasks exist: finish immediately so the upload path can be tested.
            try? await Task.sleep(for: .seconds(3))
            await model.finishSession()
        }
    }
}

@MainActor
protocol AssessmentTask {
    var kind: TaskKind { get }
    /// Runs familiarization then scored trials, returning both blocks.
    func run(recorder: SessionRecorder, hands: HandTracker, content: RealityViewContent) async -> [Block]
}
