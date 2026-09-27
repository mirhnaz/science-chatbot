import Foundation
import Observation
import ScienceCore

/// One question in a trail and what came back for it.
struct TrailStep: Identifiable {
    let id = UUID()
    let question: String
    /// Starter topic, for example "Electricity", when a trail began from one.
    var topic: String?
    var reply: TutorReply?
    var error: String?
    /// The next question asked from this step (shown as ↳ when folded).
    var chosen: String?
    /// Seconds from asking to the answer arriving, as the child waited.
    var seconds: Double?
    /// Which engine answered, for example "mir-ai-pc" or "On this iPad".
    var source: String?

    var isLoading: Bool { reply == nil && error == nil }
}

/// Screen state: the current trail (one topic's chain of questions), the
/// question box, and the starter ideas. Each question is still sent to the
/// tutor on its own. Up to three unfinished trails (this one and two earlier
/// ones) are saved on this device for 7 days so Home can offer them again
/// (see `SavedTrail`).
/// `@MainActor` keeps every change on the UI thread; model work happens inside
/// the engines and returns here when finished.
@MainActor @Observable
final class ChatModel {
    /// Steps in a full trail; after the last answer the trail is complete.
    static let trailLength = 5

    /// How long an unfinished trail is kept for "Continue your trail".
    static let keepUnfinished: TimeInterval = 7 * 24 * 60 * 60
    /// Unfinished trails Home offers: the current one and two earlier ones.
    static let openTrailLimit = 3
    private static let savedTrailsKey = "unfinishedTrails"
    /// Before 2026-09-27 only one trail was saved, under this key.
    private static let oldSavedTrailKey = "unfinishedTrail"

    var question = ""
    private(set) var steps: [TrailStep] = [] {
        didSet { persist() }
    }
    /// Identifies the current trail, so it earns only one stamp.
    private(set) var trailID = UUID()
    /// Four sparks on phones, six on wide layouts; changing it reshuffles.
    var sparkCount = 4 {
        didSet { if sparkCount != oldValue { surprise() } }
    }
    private(set) var suggestions: [Suggestion] = []
    /// Earlier unfinished trails, newest first: set aside when a new trail
    /// started, and offered again on Home.
    private(set) var shelved: [SavedTrail] = [] {
        didSet { persist() }
    }
    /// The child tapped Finish and saw Trail complete.
    private(set) var isFinished = false {
        didSet { persist() }
    }
    /// False for Debug test runs (`-autoAsk`), which must not replace a
    /// child's saved trail.
    private let persists: Bool

    private var recent = RecentSuggestions()
    private var task: Task<Void, Never>?

    var isLoading: Bool { steps.last?.isLoading ?? false }

    /// Steps with an answer, for the progress dots.
    var answeredSteps: Int { steps.count(where: { $0.reply != nil }) }

    var isComplete: Bool { answeredSteps >= Self.trailLength }

    /// A trail the child can pick up again from Home: until Finish is
    /// tapped, even after the last answer.
    var hasUnfinishedTrail: Bool { !steps.isEmpty && !isFinished }

    /// Unfinished trails for Home, newest first: the current one (if
    /// unfinished) and the earlier ones.
    var openTrails: [TrailSummary] {
        let current = hasUnfinishedTrail ? snapshot().map(TrailSummary.init) : nil
        return ([current].compactMap { $0 } + shelved.map(TrailSummary.init)).prefix(Self.openTrailLimit).map { $0 }
    }

    func markFinished() {
        isFinished = true
    }

    /// The starter topic, or nil for a question the child typed.
    var topic: String? { steps.first?.topic }

    /// The tutor's name for the trail ("Comets"), else the starter topic.
    var trailName: String? { steps.lazy.compactMap(\.reply?.trailName).first ?? topic }

    init(persists: Bool = true) {
        self.persists = persists
        if persists { restore() }
        surprise()
    }

    func surprise() {
        suggestions = BundledText.suggestionBank.select(excluding: recent.ids, count: sparkCount)
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
        run(TrailStep(question: idea.question, topic: idea.topic), using: engines)
    }

    /// A new, empty trail, before asking a question typed on Home.
    func startEmptyTrail() {
        replaceTrail()
        question = ""
    }

    /// Makes an earlier unfinished trail the current one again; the current
    /// trail (if unfinished) is set aside in its place.
    func reopen(_ id: UUID) {
        guard let saved = shelved.first(where: { $0.id == id }), let restored = Self.steps(from: saved) else { return }
        task?.cancel()
        shelved.removeAll { $0.id == id }
        shelveCurrent()
        trailID = saved.id
        isFinished = false
        steps = restored
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

    /// Starting another trail keeps this one, if unfinished, for Home.
    private func replaceTrail() {
        task?.cancel()
        shelveCurrent()
        trailID = UUID()
        isFinished = false
        steps = []
    }

    /// Sets the current trail aside (newest first), if it is unfinished and
    /// has an answer. Only the newest `openTrailLimit - 1` are kept.
    private func shelveCurrent() {
        guard !isFinished, let current = snapshot() else { return }
        shelved = Array(([current] + shelved.filter { $0.id != current.id }).prefix(Self.openTrailLimit - 1))
    }

    private func run(_ step: TrailStep, using engines: [TutorEngine]) {
        task?.cancel()
        steps.append(step)
        let id = step.id
        guard !engines.isEmpty else {
            finish(id, error: "The tutor isn’t set up yet. Ask a grown-up to check Settings → Advanced.")
            return
        }
        let started = Date()
        task = Task {
            do {
                let (reply, source) = try await Self.firstAnswer(step.question, from: engines)
                try Task.checkCancellation()
                finish(id, reply: reply, seconds: Date().timeIntervalSince(started), source: source)
            } catch is CancellationError {
                // cancel() or a new trail already updated the steps
            } catch {
                finish(id, error: error.localizedDescription)
            }
        }
    }

    private func finish(_ id: UUID, reply: TutorReply? = nil, error: String? = nil,
                        seconds: Double? = nil, source: String? = nil) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].reply = reply
        steps[index].error = error
        steps[index].seconds = seconds
        steps[index].source = source
    }

    /// Tries each engine in order; moves on only for "can't reach it" errors.
    private static func firstAnswer(_ question: String, from engines: [TutorEngine]) async throws -> (TutorReply, String) {
        for (index, engine) in engines.enumerated() {
            do {
                return (try await engine.ask(question), engine.name)
            } catch let error as TutorError where error.allowsFallback && index < engines.count - 1 {
                try Task.checkCancellation()
                continue
            }
        }
        throw TutorError.unreachable  // not reached: the last engine rethrows
    }

    // MARK: Saving unfinished trails

    /// The current trail's answered steps, or nil if it has none.
    private func snapshot() -> SavedTrail? {
        let answered = steps.compactMap { step in
            step.reply.map { SavedTrail.Step(question: step.question, topic: step.topic, chosen: step.chosen,
                                             answer: $0.answer, followUps: $0.followUps, label: $0.label,
                                             trailName: $0.trailName, fact: $0.fact) }
        }
        return answered.isEmpty ? nil : SavedTrail(id: trailID, saved: .now, steps: answered)
    }

    /// Saves the current trail (if unfinished) and the earlier ones.
    private func persist() {
        guard persists else { return }
        let current = isFinished ? nil : snapshot()
        let trails = ([current].compactMap { $0 } + shelved).prefix(Self.openTrailLimit)
        guard !trails.isEmpty, let data = try? JSONEncoder().encode(Array(trails)) else {
            UserDefaults.standard.removeObject(forKey: Self.savedTrailsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.savedTrailsKey)
    }

    /// Brings back trails saved within `keepUnfinished`: the newest becomes
    /// the current trail, the others wait on Home.
    private func restore() {
        let defaults = UserDefaults.standard
        var saved: [SavedTrail] = []
        if let data = defaults.data(forKey: Self.savedTrailsKey) {
            saved = (try? JSONDecoder().decode([SavedTrail].self, from: data)) ?? []
        } else if let data = defaults.data(forKey: Self.oldSavedTrailKey),
                  let one = try? JSONDecoder().decode(SavedTrail.self, from: data) {
            saved = [one]
        }
        defaults.removeObject(forKey: Self.oldSavedTrailKey)
        let fresh = saved.filter { Date.now.timeIntervalSince($0.saved) < Self.keepUnfinished && Self.steps(from: $0) != nil }
            .prefix(Self.openTrailLimit)
        guard let newest = fresh.first, let restored = Self.steps(from: newest) else {
            defaults.removeObject(forKey: Self.savedTrailsKey)
            return
        }
        shelved = Array(fresh.dropFirst())
        trailID = newest.id
        steps = restored
    }

    /// Trail steps from saved data, checked again like a fresh answer so old
    /// or edited data cannot show anything the tutor rules would reject; nil
    /// if any step fails.
    private static func steps(from saved: SavedTrail) -> [TrailStep]? {
        let restored = saved.steps.prefix(trailLength).compactMap { step -> TrailStep? in
            guard let reply = try? validateReply(answer: step.answer, followUps: step.followUps, label: step.label,
                                                 trailName: step.trailName, fact: step.fact)
            else { return nil }
            var trailStep = TrailStep(question: step.question, topic: step.topic, reply: reply)
            trailStep.chosen = step.chosen
            return trailStep
        }
        return restored.isEmpty || restored.count != min(saved.steps.count, trailLength) ? nil : restored
    }
}

/// What Home shows for an unfinished trail.
struct TrailSummary: Identifiable {
    let id: UUID
    let topic: String?
    let name: String?
    let question: String
    /// The latest step's label, else its question.
    let latest: String
    let answered: Int

    init(_ saved: SavedTrail) {
        id = saved.id
        topic = saved.steps.first?.topic
        name = saved.steps.lazy.compactMap(\.trailName).first ?? topic
        question = saved.steps.first?.question ?? ""
        latest = saved.steps.last.map { $0.label ?? $0.question } ?? ""
        answered = saved.steps.count
    }
}

/// An unfinished trail as saved in UserDefaults: questions, answers, and the
/// tutor's extras, with the time it was saved.
struct SavedTrail: Codable {
    struct Step: Codable {
        let question: String
        let topic: String?
        let chosen: String?
        let answer: String
        let followUps: [String]
        let label: String?
        let trailName: String?
        let fact: String?
    }

    let id: UUID
    let saved: Date
    let steps: [Step]
}
