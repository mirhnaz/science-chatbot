import Foundation
import ScienceCore

/// Sends the question to the Rust server on the AI PC, which calls Ollama.
/// The server keeps its own validation, request limit, and timeout.
struct RemoteEngine: TutorEngine {
    let baseURL: URL

    init?(address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed),
              let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil
        else { return nil }
        baseURL = url
    }

    private struct Reply: Decodable {
        let answer: String?
        let followUps: [String]?
        let error: String?
    }

    func ask(_ question: String) async throws -> TutorReply {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["question": question])
        // Slightly longer than the server's 120 s deadline so its message wins.
        request.timeoutInterval = 125

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw TutorError.timedOut
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw TutorError.unreachable
        }

        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TutorError.message(reply?.error ?? "Something went wrong. Please try again.")
        }
        guard let answer = reply?.answer, let followUps = reply?.followUps else {
            throw TutorError.message(ValidationError.emptyAnswer.description)
        }
        return try validateReply(answer: answer, followUps: followUps)
    }

    /// Uses the server's /healthz route; this does not run the model.
    func checkHealth() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
