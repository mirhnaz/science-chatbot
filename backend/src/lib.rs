//! Backend logic shared by the future HTTP server and its tests.
//!
//! Start with [`chat::validate_question`]: it borrows text and returns either a
//! trimmed slice of that same text or a typed error, without making a copy.

pub mod chat;
