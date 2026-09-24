//! Question and model-answer validation, independent of HTTP and JSON parsing.

use std::collections::HashSet;
use std::error::Error;
use std::fmt;

pub const MAX_QUESTION_LENGTH: usize = 2_000;
pub const MAX_FOLLOW_UP_LENGTH: usize = 180;
pub const FOLLOW_UP_COUNT: usize = 3;

/// Owned answer text, suitable for returning after the model response is dropped.
#[derive(Debug, PartialEq, Eq)]
pub struct TutorReply {
    pub answer: String,
    pub follow_ups: [String; FOLLOW_UP_COUNT],
}

/// Internal distinctions can be tested while preserving the existing UI messages.
#[derive(Debug, PartialEq, Eq)]
pub enum ValidationError {
    EmptyQuestion,
    QuestionTooLong,
    EmptyAnswer,
    InvalidFollowUpCount,
    EmptyFollowUp,
    FollowUpTooLong,
    DuplicateFollowUps,
}

impl fmt::Display for ValidationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::EmptyQuestion | Self::QuestionTooLong => {
                "Enter a question between 1 and 2,000 characters."
            }
            Self::EmptyAnswer
            | Self::InvalidFollowUpCount
            | Self::EmptyFollowUp
            | Self::FollowUpTooLong
            | Self::DuplicateFollowUps => {
                "The answer did not come through clearly. Could you try your question again?"
            }
        };
        formatter.write_str(message)
    }
}

impl Error for ValidationError {}

/// Validate text and return a slice that borrows from the caller's input.
///
/// The caller keeps ownership of the original string. The returned slice cannot
/// outlive it; Rust infers that lifetime relationship from this signature.
///
/// ```
/// use science_chatbot_server::chat::validate_question;
///
/// let input = String::from("  What is gravity?  ");
/// assert_eq!(validate_question(&input), Ok("What is gravity?"));
/// ```
pub fn validate_question(input: &str) -> Result<&str, ValidationError> {
    let question = trim_javascript(input);
    if question.is_empty() {
        return Err(ValidationError::EmptyQuestion);
    }
    if javascript_length(question) > MAX_QUESTION_LENGTH {
        return Err(ValidationError::QuestionTooLong);
    }
    Ok(question)
}

/// Normalize model text and require exactly three distinct follow-up questions.
///
/// This accepts typed strings. Missing fields, non-string values, and malformed
/// JSON will be handled at the JSON boundary when the Ollama client is added.
pub fn validate_reply(answer: &str, follow_ups: &[String]) -> Result<TutorReply, ValidationError> {
    let answer = trim_javascript(answer);
    if answer.is_empty() {
        return Err(ValidationError::EmptyAnswer);
    }
    if follow_ups.len() != FOLLOW_UP_COUNT {
        return Err(ValidationError::InvalidFollowUpCount);
    }

    let mut normalized = Vec::with_capacity(FOLLOW_UP_COUNT);
    let mut seen = HashSet::with_capacity(FOLLOW_UP_COUNT);
    for suggestion in follow_ups {
        let suggestion = trim_javascript(suggestion);
        if suggestion.is_empty() {
            return Err(ValidationError::EmptyFollowUp);
        }
        if javascript_length(suggestion) > MAX_FOLLOW_UP_LENGTH {
            return Err(ValidationError::FollowUpTooLong);
        }
        if !seen.insert(suggestion.to_lowercase()) {
            return Err(ValidationError::DuplicateFollowUps);
        }
        normalized.push(suggestion.to_owned());
    }

    let follow_ups = normalized
        .try_into()
        .map_err(|_| ValidationError::InvalidFollowUpCount)?;
    Ok(TutorReply {
        answer: answer.to_owned(),
        follow_ups,
    })
}

// JavaScript String.length counts UTF-16 units, not UTF-8 bytes or Rust chars.
// Preserve that limit during migration, including for emoji and non-Latin text.
fn javascript_length(text: &str) -> usize {
    text.encode_utf16().count()
}

// Match ECMAScript String.trim's WhiteSpace + LineTerminator set. Rust trim()
// also removes U+0085 and does not remove U+FEFF, unlike the current backend.
// https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-white-space
fn trim_javascript(text: &str) -> &str {
    text.trim_matches(|character| {
        matches!(
            character,
            '\u{0009}'..='\u{000D}'
                | '\u{0020}'
                | '\u{00A0}'
                | '\u{1680}'
                | '\u{2000}'..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
        )
    })
}
