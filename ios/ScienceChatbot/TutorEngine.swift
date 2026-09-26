import Foundation
import ScienceCore

/// Something that can answer one independent science question.
/// Both engines return the same validated reply type.
protocol TutorEngine: Sendable {
    func ask(_ question: String) async throws -> TutorReply
}

enum EngineChoice: String, CaseIterable, Identifiable {
    case local, remote
    var id: String { rawValue }
    var label: String { self == .local ? "On this iPad" : "My AI PC" }
}

/// Friendly errors shared by both engines, worded like the web app.
enum TutorError: LocalizedError {
    case message(String)
    case timedOut
    case unreachable

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
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
