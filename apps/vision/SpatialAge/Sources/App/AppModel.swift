import Foundation
import Observation
import RealKit
import ScoreKit

@MainActor
@Observable
final class AppModel {
    static let immersiveID = "Tasks"
    static let windowID = "Main"

    enum Phase { case onboarding, catalog, running, results }
    /// Leading tab ornament on the catalog phase (Dusk spec section 6).
    enum Tab: Hashable { case home, games, progress, duel }

    /// Two players on one headset, four rounds, one game per round. A round goes to the higher game score.
    struct Duel {
        static let rounds = 4
        static let games: [Game] = [.pendulum, .spark, .gate, .dots]
        var players: [Participant]
        var wins = [0, 0]
        var round = 1
        /// Whose turn it is within the round, 0 or 1.
        var turn = 0
        var scores: [Double?] = [nil, nil]
        var game: Game { Self.games[(round - 1) % Self.games.count] }
        var over: Bool { round > Self.rounds }
    }

    var phase: Phase
    /// Saved setup answers. Nil until first-run setup finishes on this headset.
    var profile: PlayerProfile?
    /// Setup opens on its review screen when reached from Home's "Edit setup".
    var editingSetup = false
    var tab: Tab = .home
    /// Game whose intro screen is open on the Games tab.
    var intro: Game?
    /// Dusk intro toggle "Practice round first". On by default.
    var practiceFirst = true
    var duel: Duel?
    var participant: Participant
    var queue: [Game] = Game.catalog
    var recorder: SessionRecorder?
    var ingestURL = URL(string: "http://192.168.1.10:8787")!
    var report: ScoreReport?
    var pace: PaceOfAging.Pace?
    var uploadStatus: String?

    /// Hand anatomy overlay, toggled from the main window. Works during games and on its own.
    var anatomyMode: RealHandAnatomy.Mode = .off
    /// Sky Plank height viewer (RealityHD rooftop-plank), toggled from the main window. Full immersion, no scoring.
    var skyPlank = false
    /// True while the immersive space is open (set by ImmersiveView).
    var spaceOpen = false
    /// True while the main window is on screen. The window closes while games run so it never covers the stage.
    var windowOpen = false
    /// Games run fully immersive; the anatomy viewer alone runs in passthrough.
    var passthrough = false
    /// Shown on the catalog after a session was ended before the last game.
    var notice: String?
    /// Menu music (Dusk spec section 8). Silent while a game block runs or Sky Plank is shown.
    let music = MusicBed()

    init() {
        let saved = PlayerProfile.load()
        profile = saved
        participant = saved?.participant ?? Participant(code: Participant.randomCode(), ageYears: 30)
        phase = saved == nil ? .onboarding : .catalog
        // `.running` spans every practice and scored block, so the bed can never cue timing.
        music.follow { [unowned self] in self.phase == .running || self.skyPlank }
    }

    /// The eight Dusk games, minus the standing-only ones for seated players.
    var games: [Game] {
        let skips = profile?.posture.skips ?? []
        return Game.dusk.filter { !skips.contains($0) }
    }

    /// Saves the setup answers and opens Home.
    func completeOnboarding(_ p: PlayerProfile) {
        p.save()
        profile = p
        participant = p.participant
        editingSetup = false
        tab = .home
        phase = .catalog
    }

    func editSetup() {
        editingSetup = true
        phase = .onboarding
    }

    func start(_ games: [Game]) {
        skyPlank = false
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
        guard session.blocks.contains(where: { !$0.familiarization }) else {
            abortSession("Every game was skipped. Nothing was saved.")
            return
        }
        let engine = ScoreEngine()
        report = engine.score(session)
        do { try SessionStore.save(session) } catch { uploadStatus = "save failed: \(error.localizedDescription)" }

        // Pace of aging across this participant's sessions on this device.
        let points = SessionStore.all()
            .filter { $0.participant.code == session.participant.code }
            .map(engine.score)
            .compactMap { r in r.spatialAge.map { PaceOfAging.Point(date: r.startedAt, spatialAge: $0, sd: r.spatialAgeSD ?? 5) } }
        pace = PaceOfAging.estimate(points)
        if duel != nil { advanceDuel(score: report?.games.first(where: \.played)?.score) } else { phase = .results }

        do {
            _ = try await IngestClient(baseURL: ingestURL).upload(session)
            uploadStatus = "Uploaded"
        } catch {
            uploadStatus = "Saved on device. Upload failed."
        }
    }

    /// Scored sessions for the current participant on this device, oldest first.
    func history() -> [ScoreReport] {
        let engine = ScoreEngine()
        return SessionStore.all()
            .filter { $0.participant.code == participant.code }
            .map(engine.score)
            .sorted { $0.startedAt < $1.startedAt }
    }

    func startDuel(second: Participant) {
        duel = Duel(players: [participant, second])
        tab = .duel
    }

    /// Records the finished turn, awards the round once both players have played, and hands over.
    private func advanceDuel(score: Double?) {
        guard var d = duel else { return }
        d.scores[d.turn] = score
        if d.turn == 0 {
            d.turn = 1
        } else {
            let a = d.scores[0] ?? -.infinity, b = d.scores[1] ?? -.infinity
            if a != b { d.wins[a > b ? 0 : 1] += 1 }
            d.round += 1
            d.turn = 0
            d.scores = [nil, nil]
        }
        duel = d
        participant = d.players[d.turn]
        tab = .duel
        phase = .catalog
    }

    func endDuel() {
        if let first = duel?.players.first { participant = first }
        duel = nil
        tab = .home
    }

    /// Back to the catalog for the same participant.
    func playAgain() {
        notice = nil
        tab = .games
        phase = .catalog
    }

    /// Full reset to first-run setup with a fresh participant code. Clears the saved profile.
    func nextParticipant() {
        recorder = nil
        PlayerProfile.clear()
        profile = nil
        editingSetup = false
        participant = Participant(code: Participant.randomCode(), ageYears: 30)
        report = nil
        pace = nil
        uploadStatus = nil
        notice = nil
        duel = nil
        intro = nil
        tab = .home
        phase = .onboarding
    }
}
