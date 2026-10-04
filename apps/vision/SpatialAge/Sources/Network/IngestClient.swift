import Foundation

struct IngestClient {
    let baseURL: URL

    /// POST /sessions. Returns the raw JSON response for display.
    func upload(_ session: Session) async throws -> String {
        var req = URLRequest(url: baseURL.appending(path: "sessions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Session.encoder.encode(session)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
