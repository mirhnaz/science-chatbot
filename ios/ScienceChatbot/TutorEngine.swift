import Foundation
import ScienceCore

/// Something that can answer one independent science question.
/// Both engines return the same validated reply type.
protocol TutorEngine: Sendable {
    /// Shown in the status line, for example "My AI PC".
    var name: String { get }
    func ask(_ question: String) async throws -> TutorReply
}

/// Where answers come from. Automatic tries the AI PC first and falls back
/// to the model on this iPad when the PC cannot be reached.
enum EngineChoice: String, CaseIterable, Identifiable {
    case automatic, remote, local
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .remote: return "My AI PC"
        case .local: return "On this iPad"
        }
    }
}

/// The AI PC address: the one typed in Settings, otherwise the build's
/// default host from Local.xcconfig (kept out of Git).
enum ServerAddress {
    static var builtIn: String? {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "ScienceServerHost") as? String,
              !host.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return "https://\(host.trimmingCharacters(in: .whitespaces))"
    }

    static func effective(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (builtIn ?? "") : trimmed
    }
}

/// Friendly errors shared by both engines, worded like the web app.
enum TutorError: LocalizedError {
    case message(String)
    case timedOut
    case unreachable
    /// The AI PC answered but cannot help right now (busy, restarting, or
    /// Ollama is down). Automatic mode tries the iPad instead.
    case unavailable(String)

    /// True when another engine should be tried.
    var allowsFallback: Bool {
        switch self {
        case .unreachable, .unavailable: return true
        case .message, .timedOut: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .message(let text), .unavailable(let text): return text
        case .timedOut: return "That answer took too long. Please try again."
        case .unreachable:
            return "We couldn’t reach your science tutor. Please check the connection and try again."
        }
    }
}

/// Bundled copies of the backend's tutor prompt and question bank.
enum BundledText {
    static let tutorPrompt: String = {
        guard let url = Bundle.main.url(forResource: "tutor", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("tutor.txt missing from app bundle") }
        return text
    }()

    static let suggestionBank: SuggestionBank = {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bank = try? SuggestionBank(json: data)
        else { fatalError("questions.json missing from app bundle") }
        return bank
    }()
}
