import Foundation
import QuartzCore
import ScoreKit

/// Owns the session clock and accumulates blocks. All times are seconds since `start`.
@MainActor
final class SessionRecorder {
    let start = CACurrentMediaTime()
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
    static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func save(_ session: Session) throws {
        try Session.encoder.encode(session).write(to: directory.appending(path: "\(session.sessionId).json"))
    }

    /// Past sessions on this device, for pace of aging.
    static func all() -> [Session] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap {
            try? Session.decoder.decode(Session.self, from: Data(contentsOf: $0))
        }
    }
}
