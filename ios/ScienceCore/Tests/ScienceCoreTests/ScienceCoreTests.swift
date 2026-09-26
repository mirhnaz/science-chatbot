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

    func testGrammarDescribesBothFields() {
        XCTAssertTrue(replyGrammar.contains("\\\"answer\\\""))
        XCTAssertTrue(replyGrammar.contains("\\\"followUps\\\""))
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
        XCTAssertEqual(bank.all.count, 60)
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
