import Foundation
import Observation
import RealKit
import ScoreKit

@MainActor
@Observable
final class AppModel {
    static let immersiveID = "Tasks"
    static let windowID = "Main"

    enum Phase { case consent, participant, catalog, running, results }

    var phase: Phase = .consent
    var participant = Participant(code: Participant.randomCode(), ageYears: 30)
    var queue: [Game] = Game.catalog
    var recorder: SessionRecorder?
    var ingestURL = URL(string: "http://192.168.1.10:8787")!
    var report: ScoreReport?
    var pace: PaceOfAging.Pace?
    var uploadStatus: String?

    /// Hand anatomy overlay, toggled from the main window. Works during games and on its own.
    var anatomyMode: RealHandAnatomy.Mode = .off
    /// True while the immersive space is open (set by ImmersiveView).
    var spaceOpen = false
    /// True while the main window is on screen. The window closes while games run so it never covers the stage.
    var windowOpen = false
    /// Games run fully immersive; the anatomy viewer alone runs in passthrough.
    var passthrough = false
    /// Shown on the catalog after a session was ended before the last game.
    var notice: String?

    func start(_ games: [Game]) {
        queue = games
        recorder = SessionRecorder(participant: participant)
        report = nil
        pace = nil
        uploadStatus = nil
        notice = nil
        phase = .running
    }

    /// Ends the running session without scoring. Nothing is saved.
    func abortSession(_ reason: String = "Session ended early. Nothing was saved.") {
        guard phase == .running else { return }
        recorder = nil
        notice = reason
        phase = .catalog
    }

    func finishSession() async {
        guard phase == .running, let session = recorder?.finish() else { return }
        recorder = nil
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

    /// Back to the catalog for the same participant.
    func playAgain() {
        notice = nil
        phase = .catalog
    }

    /// Full reset to the consent screen with a fresh participant code.
    func nextParticipant() {
        recorder = nil
        participant = Participant(code: Participant.randomCode(), ageYears: 30)
        report = nil
        pace = nil
        uploadStatus = nil
        notice = nil
        phase = .consent
    }
}
