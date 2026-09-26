use curio_server::chat::{
    TutorReply, ValidationError, validate_question, validate_reply,
};

fn follow_ups() -> Vec<String> {
    [
        "Why does the Moon orbit Earth?",
        "How does gravity affect ocean tides?",
        "Why do astronauts float in orbit?",
    ]
    .map(String::from)
    .to_vec()
}

#[test]
fn question_is_trimmed_without_changing_its_contents() {
    let input = String::from(" \tWhy is the sky  blue?\n ");
    let question = validate_question(&input).unwrap();
    assert_eq!(question, "Why is the sky  blue?");
    assert_eq!(input, " \tWhy is the sky  blue?\n ");
}

#[test]
fn blank_questions_are_rejected() {
    for input in ["", " \t\n\r", "\u{00A0}\u{FEFF}\u{3000}"] {
        assert_eq!(
            validate_question(input),
            Err(ValidationError::EmptyQuestion)
        );
    }
}

#[test]
fn ascii_question_limit_is_inclusive_and_applied_after_trimming() {
    let question = "x".repeat(2_000);
    let padded = format!("  {question}  ");
    assert_eq!(validate_question(&padded), Ok(question.as_str()));
    assert_eq!(
        validate_question(&"x".repeat(2_001)),
        Err(ValidationError::QuestionTooLong)
    );
}

#[test]
fn question_limit_counts_utf16_units_instead_of_utf8_bytes() {
    let question = "星".repeat(2_000);
    assert_eq!(validate_question(&question), Ok(question.as_str()));
    assert_eq!(
        validate_question(&"星".repeat(2_001)),
        Err(ValidationError::QuestionTooLong)
    );
}

#[test]
fn emoji_count_as_two_units_like_the_typescript_backend() {
    let question = "🚀".repeat(1_000);
    assert_eq!(validate_question(&question), Ok(question.as_str()));
    assert_eq!(
        validate_question(&format!("{question}?")),
        Err(ValidationError::QuestionTooLong)
    );
}

#[test]
fn trimming_matches_javascript_for_bom_and_next_line() {
    assert_eq!(
        validate_question("\u{FEFF}Gravity?\u{FEFF}"),
        Ok("Gravity?")
    );
    // JavaScript does not trim NEXT LINE (U+0085), unlike Rust's str::trim.
    assert_eq!(validate_question("\u{0085}"), Ok("\u{0085}"));
    assert_eq!(validate_question("\u{200B}"), Ok("\u{200B}"));
}

#[test]
fn valid_reply_preserves_order_and_owns_normalized_text() {
    let suggestions = follow_ups();
    let padded: Vec<String> = suggestions.iter().map(|q| format!("  {q}\n")).collect();
    let reply = validate_reply("  Gravity attracts objects.\n", &padded).unwrap();
    drop(padded);
    assert_eq!(
        reply,
        TutorReply {
            answer: "Gravity attracts objects.".into(),
            follow_ups: suggestions.try_into().unwrap(),
        }
    );
}

#[test]
fn blank_answers_are_rejected() {
    for answer in ["", " \n\t", "\u{FEFF}\u{00A0}"] {
        assert_eq!(
            validate_reply(answer, &follow_ups()),
            Err(ValidationError::EmptyAnswer)
        );
    }
}

#[test]
fn answer_length_has_no_new_limit() {
    assert!(validate_reply(&"a".repeat(5_000), &follow_ups()).is_ok());
}

#[test]
fn exactly_three_suggestions_are_required() {
    for count in [0, 1, 2, 4] {
        let suggestions: Vec<String> = (0..count).map(|i| format!("Question {i}?")).collect();
        assert_eq!(
            validate_reply("An answer", &suggestions),
            Err(ValidationError::InvalidFollowUpCount)
        );
    }
}

#[test]
fn empty_suggestions_are_rejected_in_every_position() {
    for index in 0..3 {
        let mut suggestions = follow_ups();
        suggestions[index] = " \t\u{FEFF}".into();
        assert_eq!(
            validate_reply("An answer", &suggestions),
            Err(ValidationError::EmptyFollowUp)
        );
    }
}

#[test]
fn suggestion_length_is_checked_after_trimming() {
    let mut suggestions = follow_ups();
    suggestions[0] = format!(" {} ", "x".repeat(180));
    assert!(validate_reply("An answer", &suggestions).is_ok());
    suggestions[0] = "x".repeat(181);
    assert_eq!(
        validate_reply("An answer", &suggestions),
        Err(ValidationError::FollowUpTooLong)
    );
}

#[test]
fn suggestion_limit_also_uses_utf16_units() {
    let mut suggestions = follow_ups();
    for text in ["星".repeat(180), "🚀".repeat(90)] {
        suggestions[0] = text.clone();
        assert!(validate_reply("An answer", &suggestions).is_ok());
        suggestions[0] = format!("{text}?");
        assert_eq!(
            validate_reply("An answer", &suggestions),
            Err(ValidationError::FollowUpTooLong)
        );
    }
}

#[test]
fn duplicate_suggestions_ignore_case_and_surrounding_whitespace() {
    let suggestions = [" Gravity? ", "GRAVITY?", "Light?"].map(String::from);
    assert_eq!(
        validate_reply("An answer", &suggestions),
        Err(ValidationError::DuplicateFollowUps)
    );
}

#[test]
fn duplicate_detection_uses_unicode_lowercase() {
    for pair in [["Étoile?", "étoile?"], ["ΟΣ?", "ος?"], ["İ?", "i\u{0307}?"]] {
        let suggestions = [pair[0], pair[1], "Light?"].map(String::from);
        assert_eq!(
            validate_reply("An answer", &suggestions),
            Err(ValidationError::DuplicateFollowUps)
        );
    }
}

#[test]
fn reply_trimming_matches_javascript() {
    let suggestions = ["\u{FEFF}Gravity?\u{FEFF}", "\u{0085}", "Light?"].map(String::from);
    let reply = validate_reply("\u{FEFF}Answer\u{FEFF}", &suggestions).unwrap();
    assert_eq!(reply.answer, "Answer");
    assert_eq!(reply.follow_ups[0], "Gravity?");
    assert_eq!(reply.follow_ups[1], "\u{0085}");
}

#[test]
fn validation_errors_preserve_existing_user_messages() {
    for error in [
        ValidationError::EmptyQuestion,
        ValidationError::QuestionTooLong,
    ] {
        assert_eq!(
            error.to_string(),
            "Enter a question between 1 and 2,000 characters."
        );
    }
    for error in [
        ValidationError::EmptyAnswer,
        ValidationError::InvalidFollowUpCount,
        ValidationError::EmptyFollowUp,
        ValidationError::FollowUpTooLong,
        ValidationError::DuplicateFollowUps,
    ] {
        assert_eq!(
            error.to_string(),
            "The answer did not come through clearly. Could you try your question again?"
        );
    }
}
