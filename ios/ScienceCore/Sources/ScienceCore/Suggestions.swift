import Foundation

/// One curated starter question from backend/data/questions.json.
public struct Suggestion: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let topic: String
    public let icon: String
    public let question: String
}

/// Port of backend/src/suggestions.rs: four (or, for wide layouts, six)
/// questions from different topics, preferring ones not shown recently. Runs
/// locally in both engine modes.
public struct SuggestionBank: Sendable {
    public static let recentLimit = 40
    /// Phones show four sparks; wide layouts show six.
    public static let counts = [4, 6]

    public let all: [Suggestion]

    public init(json: Data) throws {
        all = try JSONDecoder().decode([Suggestion].self, from: json)
    }

    /// Up to half come from `preferred` topics (stamps the child has not
    /// collected yet); the rest are random, and the order is shuffled.
    public func select(excluding recent: [String], count: Int = 4, preferring preferred: Set<String> = []) -> [Suggestion] {
        let excluded = Set(recent)
        // Shuffle first, then move recently shown questions to the back.
        let ordered = all.shuffled().enumerated().sorted { a, b in
            let (ea, eb) = (excluded.contains(a.element.id), excluded.contains(b.element.id))
            return ea == eb ? a.offset < b.offset : !ea
        }.map(\.element)
        var topics = Set<String>()
        var picked: [Suggestion] = []
        for question in ordered where picked.count < count / 2 && preferred.contains(question.topic) {
            if topics.insert(question.topic).inserted { picked.append(question) }
        }
        for question in ordered where picked.count < count {
            if topics.insert(question.topic).inserted { picked.append(question) }
        }
        return picked.shuffled()
    }
}

/// Remembers the last 40 displayed IDs, like the browser's sessionStorage list.
public struct RecentSuggestions: Sendable {
    public private(set) var ids: [String] = []

    public init() {}

    public mutating func record(_ shown: [Suggestion]) {
        ids.removeAll { id in shown.contains { $0.id == id } }
        ids.append(contentsOf: shown.map(\.id))
        if ids.count > SuggestionBank.recentLimit {
            ids.removeFirst(ids.count - SuggestionBank.recentLimit)
        }
    }
}
