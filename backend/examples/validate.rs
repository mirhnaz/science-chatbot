//! A small CLI exercise; this does not start a server or contact Ollama.

use curio_server::chat::validate_question;
use std::process::ExitCode;

fn main() -> ExitCode {
    let input = std::env::args().skip(1).collect::<Vec<_>>().join(" ");
    match validate_question(&input) {
        Ok(question) => {
            println!("Valid question: {question}");
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
