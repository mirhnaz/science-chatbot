import Foundation

/// An unfinished trail as saved on the device: questions, answers, and the
/// tutor's extras, with the time it was saved.
public struct SavedTrail: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public let question: String
        public let topic: String?
        public let chosen: String?
        public let answer: String
        public let followUps: [String]
        public let label: String?
        public let trailName: String?
        public let fact: String?

        public init(question: String, topic: String?, chosen: String?, answer: String, followUps: [String],
                    label: String? = nil, trailName: String? = nil, fact: String? = nil) {
            self.question = question
            self.topic = topic
            self.chosen = chosen
            self.answer = answer
            self.followUps = followUps
            self.label = label
            self.trailName = trailName
            self.fact = fact
        }
    }

    public let id: UUID
    public let saved: Date
    public let steps: [Step]

    public init(id: UUID, saved: Date, steps: [Step]) {
        self.id = id
        self.saved = saved
        self.steps = steps
    }

    /// The steps' replies, checked again like fresh answers (so old or edited
    /// data cannot show anything the tutor rules would reject), up to
    /// `limit` steps; nil if the trail is empty or any step fails.
    public func validatedReplies(limit: Int) -> [TutorReply]? {
        let replies = steps.prefix(limit).compactMap { step in
            try? validateReply(answer: step.answer, followUps: step.followUps, label: step.label,
                               trailName: step.trailName, fact: step.fact)
        }
        return replies.isEmpty || replies.count != min(steps.count, limit) ? nil : replies
    }
}

/// Up to three unfinished trails: the current one (kept by the app) and the
/// earlier ones on this shelf, newest first. Pure logic, so `swift test`
/// covers it; the app stores the list in UserDefaults.
public struct OpenTrailShelf: Equatable, Sendable {
    /// Unfinished trails Home offers, the current one included.
    public static let limit = 3
    /// How long an unfinished trail is kept.
    public static let keep: TimeInterval = 7 * 24 * 60 * 60

    public private(set) var earlier: [SavedTrail]

    public init(earlier: [SavedTrail] = []) {
        self.earlier = Array(earlier.prefix(Self.limit - 1))
    }

    /// Sets a trail aside, newest first; only the newest `limit - 1` stay.
    /// Nil (a finished or empty trail) changes nothing.
    public mutating func shelve(_ trail: SavedTrail?) {
        guard let trail else { return }
        earlier = Array(([trail] + earlier.filter { $0.id != trail.id }).prefix(Self.limit - 1))
    }

    /// Takes an earlier trail off the shelf to reopen it, setting `current`
    /// aside in its place. Nil if there is no such trail.
    public mutating func reopen(_ id: UUID, replacing current: SavedTrail?) -> SavedTrail? {
        guard let chosen = earlier.first(where: { $0.id == id }) else { return nil }
        earlier.removeAll { $0.id == id }
        shelve(current)
        return chosen
    }

    /// What to save: the current trail first (if unfinished), then the shelf.
    public func toSave(current: SavedTrail?) -> [SavedTrail] {
        Array(([current].compactMap { $0 } + earlier).prefix(Self.limit))
    }

    /// From saved trails: those saved within `keep` of `now` and passing
    /// `isValid`. The newest becomes the current trail, the rest the shelf.
    public static func restore(_ saved: [SavedTrail], now: Date,
                               isValid: (SavedTrail) -> Bool) -> (current: SavedTrail?, shelf: OpenTrailShelf) {
        let fresh = saved.filter { trail in
            let age = now.timeIntervalSince(trail.saved)
            return age >= 0 && age < keep && isValid(trail)
        }.prefix(limit)
        return (fresh.first, OpenTrailShelf(earlier: Array(fresh.dropFirst())))
    }

    /// Decodes the saved list, or one trail saved by the older single-trail
    /// version; nothing for missing or unreadable data.
    public static func decode(list: Data?, single: Data?) -> [SavedTrail] {
        if let list { return (try? JSONDecoder().decode([SavedTrail].self, from: list)) ?? [] }
        if let single, let one = try? JSONDecoder().decode(SavedTrail.self, from: single) { return [one] }
        return []
    }
}
