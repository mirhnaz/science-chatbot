import Foundation
import Observation
import ScienceCore

/// Screen state for one question at a time, like the web app.
/// `@MainActor` keeps every change on the UI thread; model work happens
/// inside the engines and returns here when finished.
@MainActor @Observable
final class ChatModel {
    var question = ""
    private(set) var askedQuestion = ""
    private(set) var reply: TutorReply?
    private(set) var errorText: String?
    private(set) var status = "Ready when you are."
    private(set) var isLoading = false
    private(set) var suggestions: [Suggestion] = []

    private var recent = RecentSuggestions()
    private var task: Task<Void, Never>?

    init() {
        surprise()
    }

    func surprise() {
        suggestions = BundledText.suggestionBank.select(excluding: recent.ids)
        recent.record(suggestions)
    }

    /// `engines` is in preference order. If one cannot be reached, the next
    /// is tried (Automatic mode: AI PC, then this iPad).
    func ask(_ text: String? = nil, using engines: [TutorEngine]) {
        if let text { question = text }
        let question: String
        do {
            question = try validateQuestion(self.question)
        } catch {
            errorText = (error as? ValidationError)?.description
            return
        }
        guard !engines.isEmpty else {
            errorText = "Choose a tutor in Settings: download a model or enter your AI PC address."
            return
        }

        task?.cancel()
        askedQuestion = question
        reply = nil
        errorText = nil
        isLoading = true
        status = "Working on your answer…"
        let started = Date()

        task = Task {
            do {
                let (result, source) = try await Self.firstAnswer(question, from: engines) { name in
                    self.status = "Working on your answer on \(name)…"
                }
                try Task.checkCancellation()
                reply = result
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                status = "Answered by \(source) in \(seconds) seconds."
            } catch is CancellationError {
                status = "Question cancelled."
            } catch {
                errorText = error.localizedDescription
                status = "Ready to try again."
            }
            isLoading = false
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Tries each engine in order; moves on only for "can't reach it" errors.
    /// `switching` reports the engine being tried after a fallback.
    private static func firstAnswer(
        _ question: String, from engines: [TutorEngine], switching: (String) -> Void
    ) async throws -> (TutorReply, String) {
        for (index, engine) in engines.enumerated() {
            if index > 0 { switching(engine.name) }
            do {
                return (try await engine.ask(question), engine.name)
            } catch let error as TutorError where error.allowsFallback && index < engines.count - 1 {
                try Task.checkCancellation()
                continue
            }
        }
        throw TutorError.unreachable  // not reached: the last engine rethrows
    }
}
