import Foundation
import QuartzCore
import ScoreKit

/// Owns the session clock and accumulates blocks. All times are seconds since `start`.
@MainActor
final class SessionRecorder {
    let start = CACurrentMediaTime()
    private(set) var session: Session

    init(participant: Participant, mode: PlayMode, priorSessions: Int) {
        let info = Bundle.main.infoDictionary
        session = Session(
            participant: participant,
            device: Device(model: Self.hardwareModel, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                           appVersion: info?["CFBundleShortVersionString"] as? String ?? "0", deviceId: Self.deviceId),
            mode: mode,
            priorSessions: priorSessions
        )
    }

    /// Hardware identifier such as `RealityDevice14,1`.
    static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// Random id made once per install. Tells headsets apart without identifying anyone.
    static var deviceId: String {
        let key = "sa.deviceId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
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

    private static let uploadedKey = "sa.uploaded"

    /// Saved sessions ingest has not acknowledged, oldest first. Files stay on the device until then.
    static func pending() -> [Session] {
        let done = Set(UserDefaults.standard.stringArray(forKey: uploadedKey) ?? [])
        return all().filter { !done.contains($0.sessionId) }.sorted { $0.startedAt < $1.startedAt }
    }

    static func markUploaded(_ id: String) {
        var done = UserDefaults.standard.stringArray(forKey: uploadedKey) ?? []
        if !done.contains(id) { done.append(id) }
        UserDefaults.standard.set(done, forKey: uploadedKey)
    }

    /// Past sessions on this device, for pace of aging.
    static func all() -> [Session] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap {
            try? Session.decoder.decode(Session.self, from: Data(contentsOf: $0))
        }
    }
}
