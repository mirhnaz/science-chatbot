//! Science Chatbot: validation and an asynchronous HTTP server.
//!
//! Start with [`chat::validate_question`]: it borrows text and returns either a
//! trimmed slice of that same text or a typed error, without making a copy.

pub mod chat;
pub mod http;
pub mod suggestions;
