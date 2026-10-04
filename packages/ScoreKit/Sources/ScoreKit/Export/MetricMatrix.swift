import Foundation

/// One row per session for the KDM age model (`ml/sha_biomarkers/kdm.py`): who played and how, then every
/// metric value by id. An empty cell is a metric the session did not produce. Metrics are recomputed from the
/// raw sessions each time, so a change to an extractor reaches the matrix without re-collecting data.
public enum MetricMatrix {
    public static let infoColumns = [
        "session_id", "code", "started_at", "age", "sex", "handedness", "height_cm", "weight_kg", "posture",
        "mode", "prior_sessions", "calibration", "usable", "device_id", "device_model", "app_version",
        "schema_version",
    ]
    public static var columns: [String] { infoColumns + MetricID.allCases.map(\.rawValue) }

    /// Sessions that may calibrate norms: usable, played as Play all (or pre-0.5 with no mode), and the first
    /// such session for its participant code, so practice does not leak in.
    public static func calibrationIDs(_ rows: [(Session, ScoreReport)]) -> Set<String> {
        var first: [String: (Date, String)] = [:]
        for (s, r) in rows where r.quality.usable && (s.mode == nil || s.mode == .full) {
            let code = s.participant.code
            if let f = first[code], f.0 <= s.startedAt { continue }
            first[code] = (s.startedAt, s.sessionId)
        }
        return Set(first.values.map(\.1))
    }

    public static func csv(_ sessions: [Session], engine: ScoreEngine = ScoreEngine()) -> String {
        let rows = sessions.sorted { $0.startedAt < $1.startedAt }.map { ($0, engine.score($0)) }
        let calibration = calibrationIDs(rows)
        let date = ISO8601DateFormatter()
        var lines = [columns.joined(separator: ",")]
        for (s, r) in rows {
            let p = s.participant
            let values = Dictionary(r.metrics.map { ($0.id, $0.value) }, uniquingKeysWith: { a, _ in a })
            let info: [String] = [
                s.sessionId, p.code, date.string(from: s.startedAt), num(p.ageYears), p.sex.rawValue,
                p.handedness.rawValue, num(p.heightCm), num(p.weightKg), p.posture?.rawValue ?? "",
                s.mode?.rawValue ?? "", s.priorSessions.map(String.init) ?? "",
                calibration.contains(s.sessionId) ? "1" : "0", r.quality.usable ? "1" : "0",
                s.device.deviceId ?? "", s.device.model, s.device.appVersion, s.schemaVersion,
            ]
            let metrics = MetricID.allCases.map { num(values[$0]) }
            lines.append((info + metrics).map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func num(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.6g", v)
    }

    static func escape(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
