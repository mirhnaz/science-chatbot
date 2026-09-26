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

    func ask(_ text: String? = nil, using engine: TutorEngine?) {
        if let text { question = text }
        let question: String
        do {
            question = try validateQuestion(self.question)
        } catch {
            errorText = (error as? ValidationError)?.description
            return
        }
        guard let engine else {
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
                let result = try await engine.ask(question)
                try Task.checkCancellation()
                reply = result
                status = String(format: "Answered in %.1f seconds.", Date().timeIntervalSince(started))
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
}
