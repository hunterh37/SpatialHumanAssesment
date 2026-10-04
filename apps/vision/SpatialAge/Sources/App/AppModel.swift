import Foundation
import Observation
import ScoreKit

@MainActor
@Observable
final class AppModel {
    static let immersiveID = "Tasks"

    enum Phase { case consent, participant, catalog, running, results }

    var phase: Phase = .consent
    var participant = Participant(code: Participant.randomCode(), ageYears: 30)
    var queue: [Game] = Game.allCases
    var recorder: SessionRecorder?
    var ingestURL = URL(string: "http://192.168.1.10:8787")!
    var report: ScoreReport?
    var pace: PaceOfAging.Pace?
    var uploadStatus: String?

    func start(_ games: [Game]) {
        queue = games
        recorder = SessionRecorder(participant: participant)
        report = nil
        phase = .running
    }

    func finishSession() async {
        guard let session = recorder?.finish() else { return }
        let engine = ScoreEngine()
        report = engine.score(session)
        do { try SessionStore.save(session) } catch { uploadStatus = "save failed: \(error.localizedDescription)" }

        // Pace of aging across this participant's sessions on this device.
        let points = SessionStore.all()
            .filter { $0.participant.code == session.participant.code }
            .map(engine.score)
            .compactMap { r in r.spatialAge.map { PaceOfAging.Point(date: r.startedAt, spatialAge: $0, sd: r.spatialAgeSD ?? 5) } }
        pace = PaceOfAging.estimate(points)
        phase = .results

        do {
            _ = try await IngestClient(baseURL: ingestURL).upload(session)
            uploadStatus = "Uploaded"
        } catch {
            uploadStatus = "Saved on device. Upload failed."
        }
    }

    func nextParticipant() {
        participant = Participant(code: Participant.randomCode(), ageYears: 30)
        report = nil
        pace = nil
        uploadStatus = nil
        phase = .consent
    }
}
