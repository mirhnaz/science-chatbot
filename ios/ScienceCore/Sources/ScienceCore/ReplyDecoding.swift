import Foundation

/// The JSON shape both the model and the Rust server produce.
struct RawReply: Decodable {
    let answer: String
    let followUps: [String]
}

/// Decodes the model's JSON text, then applies the same checks as the server.
public func decodeReply(_ text: String) throws -> TutorReply {
    guard let data = text.data(using: .utf8),
          let raw = try? JSONDecoder().decode(RawReply.self, from: data)
    else { throw ValidationError.emptyAnswer }
    return try validateReply(answer: raw.answer, followUps: raw.followUps)
}
