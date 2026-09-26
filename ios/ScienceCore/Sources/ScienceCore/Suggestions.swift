import Foundation

/// One curated starter question from backend/data/questions.json.
public struct Suggestion: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let topic: String
    public let icon: String
    public let question: String
}

/// Port of backend/src/suggestions.rs: four questions from different topics,
/// preferring ones not shown recently. Runs locally in both engine modes.
public struct SuggestionBank: Sendable {
    public static let recentLimit = 40
    static let count = 4

    public let all: [Suggestion]

    public init(json: Data) throws {
        all = try JSONDecoder().decode([Suggestion].self, from: json)
    }

    public func select(excluding recent: [String]) -> [Suggestion] {
        let excluded = Set(recent)
        // Shuffle first, then move recently shown questions to the back.
        let ordered = all.shuffled().enumerated().sorted { a, b in
            let (ea, eb) = (excluded.contains(a.element.id), excluded.contains(b.element.id))
            return ea == eb ? a.offset < b.offset : !ea
        }
        var topics = Set<String>()
        return ordered.map(\.element)
            .filter { topics.insert($0.topic).inserted }
            .prefix(Self.count)
            .map { $0 }
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
