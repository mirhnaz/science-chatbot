import Foundation
import Observation
import ScienceCore

/// One question in a trail and what came back for it.
struct TrailStep: Identifiable {
    let id = UUID()
    let question: String
    /// Starter topic, for example "⚡ Electricity", when a trail began from one.
    var topic: String?
    var reply: TutorReply?
    var error: String?
    /// The next question asked from this step (shown as ↳ when folded).
    var chosen: String?

    var isLoading: Bool { reply == nil && error == nil }
}

/// Screen state: the current trail (one topic's chain of questions), the
/// question box, and the starter ideas. Each question is still sent to the
/// tutor on its own; the trail is only kept on this device for this session.
/// `@MainActor` keeps every change on the UI thread; model work happens inside
/// the engines and returns here when finished.
@MainActor @Observable
final class ChatModel {
    var question = ""
    private(set) var steps: [TrailStep] = []
    private(set) var suggestions: [Suggestion] = []
    /// The trail replaced by "something new", kept briefly for Undo.
    private(set) var undoSteps: [TrailStep]?

    private var recent = RecentSuggestions()
    private var task: Task<Void, Never>?

    var isLoading: Bool { steps.last?.isLoading ?? false }

    init() {
        surprise()
    }

    func surprise() {
        suggestions = BundledText.suggestionBank.select(excluding: recent.ids)
        recent.record(suggestions)
    }

    /// Asks `text` (or the question box) as the next step of this trail.
    func ask(_ text: String? = nil, using engines: [TutorEngine]) {
        let asked: String
        do {
            asked = try validateQuestion(text ?? question)
        } catch {
            return  // the send button is disabled for empty questions
        }
        if text == nil { question = "" }  // the question moves into the trail
        if !steps.isEmpty { steps[steps.count - 1].chosen = asked }
        run(TrailStep(question: asked), using: engines)
    }

    /// "Try something new": starts a new trail with a starter question.
    func startTrail(with idea: Suggestion, using engines: [TutorEngine]) {
        replaceTrail()
        surprise()
        run(TrailStep(question: idea.question, topic: "\(idea.icon) \(idea.topic)"), using: engines)
    }

    /// "Ask your own": a new, empty trail with the question box ready.
    func startEmptyTrail() {
        replaceTrail()
        question = ""
    }

    func undo() {
        guard let previous = undoSteps else { return }
        task?.cancel()
        steps = previous
        undoSteps = nil
    }

    func clearUndo() {
        undoSteps = nil
    }

    /// Asks a failed question again.
    func retry(using engines: [TutorEngine]) {
        guard let last = steps.last, last.error != nil else { return }
        steps.removeLast()
        var again = TrailStep(question: last.question)
        again.topic = last.topic
        run(again, using: engines)
    }

    /// Stops the current answer and puts the question back in the box.
    func cancel() {
        guard let last = steps.last, last.isLoading else { return }
        task?.cancel()
        steps.removeLast()
        if !steps.isEmpty { steps[steps.count - 1].chosen = nil }
        question = last.question
    }

    private func replaceTrail() {
        task?.cancel()
        undoSteps = steps.contains { $0.reply != nil } ? steps : nil
        steps = []
    }

    private func run(_ step: TrailStep, using engines: [TutorEngine]) {
        task?.cancel()
        steps.append(step)
        let id = step.id
        guard !engines.isEmpty else {
            finish(id, error: "The tutor isn’t set up yet. Ask a grown-up to check Settings → Advanced.")
            return
        }
        task = Task {
            do {
                let reply = try await Self.firstAnswer(step.question, from: engines)
                try Task.checkCancellation()
                finish(id, reply: reply)
            } catch is CancellationError {
                // cancel() or a new trail already updated the steps
            } catch {
                finish(id, error: error.localizedDescription)
            }
        }
    }

    private func finish(_ id: UUID, reply: TutorReply? = nil, error: String? = nil) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].reply = reply
        steps[index].error = error
    }

    /// Tries each engine in order; moves on only for "can't reach it" errors.
    private static func firstAnswer(_ question: String, from engines: [TutorEngine]) async throws -> TutorReply {
        for (index, engine) in engines.enumerated() {
            do {
                return try await engine.ask(question)
            } catch let error as TutorError where error.allowsFallback && index < engines.count - 1 {
                try Task.checkCancellation()
                continue
            }
        }
        throw TutorError.unreachable  // not reached: the last engine rethrows
    }
}
