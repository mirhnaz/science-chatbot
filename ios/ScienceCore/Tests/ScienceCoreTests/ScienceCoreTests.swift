import Foundation
import XCTest
@testable import ScienceCore

// Mirrors backend/tests/validation.rs so the iPad and the server agree.
final class ValidationTests: XCTestCase {
    let followUps = [
        "Why does the Moon orbit Earth?",
        "How does gravity affect ocean tides?",
        "Why do astronauts float in orbit?",
    ]

    func testQuestionIsTrimmed() throws {
        XCTAssertEqual(try validateQuestion(" \tWhy is the sky  blue?\n "), "Why is the sky  blue?")
    }

    func testBlankQuestionsAreRejected() {
        for input in ["", " \t\n\r", "\u{00A0}\u{FEFF}\u{3000}"] {
            XCTAssertThrowsError(try validateQuestion(input)) {
                XCTAssertEqual($0 as? ValidationError, .emptyQuestion)
            }
        }
    }

    func testQuestionLimitUsesUTF16Units() throws {
        for unit in ["x", "星"] {
            let question = String(repeating: unit, count: 2_000)
            XCTAssertEqual(try validateQuestion("  \(question)  "), question)
            XCTAssertThrowsError(try validateQuestion(question + unit))
        }
        let rockets = String(repeating: "🚀", count: 1_000)
        XCTAssertEqual(try validateQuestion(rockets), rockets)
        XCTAssertThrowsError(try validateQuestion(rockets + "?"))
    }

    func testTrimmingMatchesJavaScript() throws {
        XCTAssertEqual(try validateQuestion("\u{FEFF}Gravity?\u{FEFF}"), "Gravity?")
        XCTAssertEqual(try validateQuestion("\u{0085}"), "\u{0085}")
        XCTAssertEqual(try validateQuestion("\u{200B}"), "\u{200B}")
    }

    func testValidReplyIsNormalized() throws {
        let reply = try validateReply(
            answer: "  Gravity attracts objects.\n",
            followUps: followUps.map { "  \($0)\n" })
        XCTAssertEqual(reply, TutorReply(answer: "Gravity attracts objects.", followUps: followUps))
    }

    func testReplyRules() {
        XCTAssertThrowsError(try validateReply(answer: "\u{FEFF}\u{00A0}", followUps: followUps))
        XCTAssertNoThrow(try validateReply(answer: String(repeating: "a", count: 5_000), followUps: followUps))
        for count in [0, 1, 2, 4] {
            let items = (0..<count).map { "Question \($0)?" }
            XCTAssertThrowsError(try validateReply(answer: "An answer", followUps: items)) {
                XCTAssertEqual($0 as? ValidationError, .invalidFollowUpCount)
            }
        }
        var items = followUps
        items[0] = " \(String(repeating: "x", count: 180)) "
        XCTAssertNoThrow(try validateReply(answer: "An answer", followUps: items))
        items[0] = String(repeating: "🚀", count: 90) + "?"
        XCTAssertThrowsError(try validateReply(answer: "An answer", followUps: items)) {
            XCTAssertEqual($0 as? ValidationError, .followUpTooLong)
        }
        items[0] = followUps[1].uppercased()
        XCTAssertThrowsError(try validateReply(answer: "An answer", followUps: items)) {
            XCTAssertEqual($0 as? ValidationError, .duplicateFollowUps)
        }
    }

    func testDecodeReply() throws {
        let json = #"{"answer":"Light scatters.","followUps":["A?","B?","C?"]}"#
        XCTAssertEqual(try decodeReply(json).followUps, ["A?", "B?", "C?"])
        XCTAssertThrowsError(try decodeReply("not json"))
    }

    func testDecodeReplyKeepsUsableExtrasOnly() throws {
        let json = #"{"answer":"Ice and dust.","fact":" Comets are dirty snowballs. ","label":"The nucleus","trailName":"\#(String(repeating: "x", count: 31))","followUps":["A?","B?","C?"]}"#
        let reply = try decodeReply(json)
        XCTAssertEqual(reply.fact, "Comets are dirty snowballs.")
        XCTAssertEqual(reply.label, "The nucleus")
        XCTAssertNil(reply.trailName, "too long: dropped, not an error")
        XCTAssertNil(optionalText("   ", limit: 40))
    }

    func testGrammarDescribesEveryField() {
        for field in ["answer", "fact", "label", "trailName", "followUps"] {
            XCTAssertTrue(replyGrammar.contains("\\\"\(field)\\\""), field)
        }
    }
}

final class SuggestionTests: XCTestCase {
    // Uses the real bank that the app bundles, so edits are checked too.
    func bank() throws -> SuggestionBank {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("backend/data/questions.json")
        return try SuggestionBank(json: Data(contentsOf: url))
    }

    func testSelectionIsDiverseAndAvoidsRecent() throws {
        let bank = try bank()
        XCTAssertEqual(bank.all.count, 66)
        XCTAssertEqual(Set(bank.all.map(\.topic)).count, 11)
        for _ in 0..<50 {
            let picked = bank.select(excluding: [], count: 4, preferring: ["Body", "Plants", "Light"])
            XCTAssertGreaterThanOrEqual(picked.filter { ["Body", "Plants", "Light"].contains($0.topic) }.count, 2)
            XCTAssertEqual(Set(picked.map(\.topic)).count, 4)
        }
        let six = bank.select(excluding: [], count: 6)
        XCTAssertEqual(six.count, 6)
        XCTAssertEqual(Set(six.map(\.topic)).count, 6)
        var recent = RecentSuggestions()
        for _ in 0..<10 {
            let picked = bank.select(excluding: recent.ids)
            XCTAssertEqual(picked.count, 4)
            XCTAssertEqual(Set(picked.map(\.topic)).count, 4)
            XCTAssertTrue(Set(picked.map(\.id)).isDisjoint(with: recent.ids.suffix(8)))
            recent.record(picked)
            XCTAssertLessThanOrEqual(recent.ids.count, SuggestionBank.recentLimit)
        }
    }
}

final class OpenTrailShelfTests: XCTestCase {
    private func trail(_ name: String, savedAgo: TimeInterval = 0, answer: String = "An answer.",
                       now: Date = Date(timeIntervalSince1970: 1_000_000)) -> SavedTrail {
        SavedTrail(id: UUID(), saved: now.addingTimeInterval(-savedAgo),
                   steps: [.init(question: "\(name)?", topic: "Space", chosen: nil, answer: answer,
                                 followUps: ["A?", "B?", "C?"], trailName: name)])
    }

    func testShelvingKeepsTheTwoNewestEarlierTrails() {
        var shelf = OpenTrailShelf()
        let (a, b, c) = (trail("A"), trail("B"), trail("C"))
        shelf.shelve(a); shelf.shelve(b); shelf.shelve(c)
        XCTAssertEqual(shelf.earlier.map(\.id), [c.id, b.id], "newest first; the oldest drops off")
        shelf.shelve(nil)
        XCTAssertEqual(shelf.earlier.count, 2, "a finished trail (nil) changes nothing")
        shelf.shelve(b)
        XCTAssertEqual(shelf.earlier.map(\.id), [b.id, c.id], "shelving again moves it to the front, no duplicate")
    }

    func testReopeningSwapsWithTheCurrentTrail() {
        let (a, b, current) = (trail("A"), trail("B"), trail("Now"))
        var shelf = OpenTrailShelf(earlier: [a, b])
        XCTAssertEqual(shelf.reopen(b.id, replacing: current), b)
        XCTAssertEqual(shelf.earlier.map(\.id), [current.id, a.id])
        XCTAssertNil(shelf.reopen(UUID(), replacing: nil), "unknown trail")
        XCTAssertEqual(shelf.toSave(current: b).map(\.id), [b.id, current.id, a.id], "current first, at most three")
        XCTAssertEqual(shelf.toSave(current: nil).map(\.id), [current.id, a.id], "a finished current trail is not saved")
    }

    func testRestoreDropsOldAndInvalidTrails() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = trail("Fresh", savedAgo: 60, now: now)
        let sixDays = trail("Six days", savedAgo: 6 * 86_400, now: now)
        let eightDays = trail("Eight days", savedAgo: 8 * 86_400, now: now)
        let future = trail("Future", savedAgo: -60, now: now)
        let broken = trail("Broken", answer: "   ", now: now)
        let (current, shelf) = OpenTrailShelf.restore([fresh, eightDays, broken, future, sixDays], now: now) {
            $0.validatedReplies(limit: 5) != nil
        }
        XCTAssertEqual(current, fresh)
        XCTAssertEqual(shelf.earlier, [sixDays], "over a week old, future-dated, or failing the reply rules: dropped")
    }

    func testDecodeReadsTheListOrTheOlderSingleTrail() throws {
        let one = trail("Old")
        let single = try JSONEncoder().encode(one)
        XCTAssertEqual(OpenTrailShelf.decode(list: nil, single: single), [one])
        let list = try JSONEncoder().encode([one, trail("Two")])
        XCTAssertEqual(OpenTrailShelf.decode(list: list, single: single).count, 2, "the list wins")
        XCTAssertEqual(OpenTrailShelf.decode(list: Data("not json".utf8), single: nil), [])
    }

    func testValidatedRepliesKeepTheExtrasAndRejectBadSteps() {
        XCTAssertEqual(trail("Comets").validatedReplies(limit: 5)?.first?.trailName, "Comets")
        XCTAssertNil(trail("Bad", answer: "").validatedReplies(limit: 5))
        let empty = SavedTrail(id: UUID(), saved: .now, steps: [])
        XCTAssertNil(empty.validatedReplies(limit: 5))
    }
}
