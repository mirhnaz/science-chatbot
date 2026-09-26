/// GBNF grammar for llama.cpp that only allows JSON shaped like
/// backend/src/reply-schema.json: {"answer": "...", "followUps": [three strings]}.
/// This is the on-device equivalent of Ollama's `format` option. The follow-up
/// limit counts JSON characters, so validateReply still has the final say.
/// Whitespace is bounded so the model cannot loop on blank output.
public let replyGrammar = #"""
root      ::= "{" ws "\"answer\"" ws ":" ws answer ws "," ws "\"followUps\"" ws ":" ws "[" ws followup ws "," ws followup ws "," ws followup ws "]" ws "}"
answer    ::= "\"" char+ "\""
followup  ::= "\"" char{1,180} "\""
char      ::= [^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
ws        ::= [ \t\n]{0,4}
"""#
