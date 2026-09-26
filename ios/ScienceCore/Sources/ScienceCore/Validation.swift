// Swift port of backend/src/chat.rs. Keep the limits, trimming, and messages
// identical so both engines treat questions and replies the same way.

public let maxQuestionLength = 2_000
public let maxFollowUpLength = 180
public let followUpCount = 3

public struct TutorReply: Equatable, Sendable {
    public let answer: String
    public let followUps: [String]

    public init(answer: String, followUps: [String]) {
        self.answer = answer
        self.followUps = followUps
    }
}

public enum ValidationError: Error, Equatable, CustomStringConvertible {
    case emptyQuestion
    case questionTooLong
    case emptyAnswer
    case invalidFollowUpCount
    case emptyFollowUp
    case followUpTooLong
    case duplicateFollowUps

    public var description: String {
        switch self {
        case .emptyQuestion, .questionTooLong:
            return "Enter a question between 1 and 2,000 characters."
        default:
            return "The answer did not come through clearly. Could you try your question again?"
        }
    }
}

public func validateQuestion(_ input: String) throws -> String {
    let question = trimJavaScript(input)
    if question.isEmpty { throw ValidationError.emptyQuestion }
    // UTF-16 code units match the browser's maxlength and the Rust limit.
    if question.utf16.count > maxQuestionLength { throw ValidationError.questionTooLong }
    return question
}

public func validateReply(answer: String, followUps: [String]) throws -> TutorReply {
    let answer = trimJavaScript(answer)
    if answer.isEmpty { throw ValidationError.emptyAnswer }
    if followUps.count != followUpCount { throw ValidationError.invalidFollowUpCount }

    var normalized: [String] = []
    var seen = Set<String>()
    for suggestion in followUps {
        let suggestion = trimJavaScript(suggestion)
        if suggestion.isEmpty { throw ValidationError.emptyFollowUp }
        if suggestion.utf16.count > maxFollowUpLength { throw ValidationError.followUpTooLong }
        if !seen.insert(suggestion.lowercased()).inserted { throw ValidationError.duplicateFollowUps }
        normalized.append(suggestion)
    }
    return TutorReply(answer: answer, followUps: normalized)
}

/// The whitespace set JavaScript's String.trim removes (and Rust mirrors).
/// Swift's own whitespace set differs, e.g. it also trims U+0085.
func isJavaScriptSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A,
         0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
        return true
    default:
        return false
    }
}

func trimJavaScript(_ text: String) -> String {
    let scalars = text.unicodeScalars
    guard let start = scalars.firstIndex(where: { !isJavaScriptSpace($0) }),
          let end = scalars.lastIndex(where: { !isJavaScriptSpace($0) })
    else { return "" }
    return String(scalars[start...end])
}
