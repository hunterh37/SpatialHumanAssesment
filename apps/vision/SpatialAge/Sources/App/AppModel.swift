import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let immersiveID = "Tasks"

    enum Phase { case consent, participant, running, results }

    var phase: Phase = .consent
    var participant = Participant(code: Participant.randomCode(), ageYears: 30, sex: .unspecified, handedness: .right)
    var recorder: SessionRecorder?
    var ingestURL = URL(string: "http://192.168.1.10:8787")!
    var lastResult: String?

    func startSession() {
        recorder = SessionRecorder(participant: participant)
        phase = .running
    }

    func finishSession() async {
        guard let session = recorder?.finish() else { return }
        do {
            try SessionStore.save(session)
            lastResult = try await IngestClient(baseURL: ingestURL).upload(session)
        } catch {
            lastResult = "upload failed: \(error.localizedDescription). Saved locally."
        }
        phase = .results
    }
}
