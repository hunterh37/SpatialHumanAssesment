import Foundation
import QuartzCore

/// Owns the session clock and accumulates blocks. All times are seconds since `start`.
@MainActor
final class SessionRecorder {
    private let start = CACurrentMediaTime()
    private(set) var session: Session

    init(participant: Participant) {
        let info = Bundle.main.infoDictionary
        session = Session(
            participant: participant,
            device: Device(model: "RealityDevice", osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                           appVersion: info?["CFBundleShortVersionString"] as? String ?? "0")
        )
    }

    var now: Double { CACurrentMediaTime() - start }

    func append(_ block: Block) { session.blocks.append(block) }

    func finish() -> Session { session }
}

enum SessionStore {
    static func save(_ session: Session) throws {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try Session.encoder.encode(session).write(to: dir.appending(path: "\(session.sessionId).json"))
    }
}
