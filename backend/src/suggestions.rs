//! Curated starter questions. Selection is local and never calls the model.
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashSet, hash_map::RandomState},
    hash::BuildHasher,
    sync::OnceLock,
};

pub const RECENT_LIMIT: usize = 40;
/// Phones show four sparks; wide layouts (iPad landscape, web) show six.
pub const COUNTS: [usize; 2] = [4, 6];

#[derive(Debug, Deserialize, Serialize)]
pub struct Suggestion {
    pub id: String,
    pub topic: String,
    pub icon: String,
    pub question: String,
}

pub fn bank() -> &'static [Suggestion] {
    static BANK: OnceLock<Vec<Suggestion>> = OnceLock::new();
    BANK.get_or_init(|| {
        serde_json::from_str(include_str!("../data/questions.json"))
            .expect("valid embedded question bank")
    })
}

/// `count` questions from different topics, preferring ones not in `excluded`.
/// Up to half come from `preferred` topics (the stamps a child has not
/// collected yet); the rest are random, and the order is shuffled.
pub fn select(excluded: &[&str], count: usize, preferred: &[&str]) -> Vec<&'static Suggestion> {
    // A fresh randomly seeded hash orders the small bank differently per call.
    // This is for variety, not security, and needs no shared mutable counter.
    let random = RandomState::new();
    let mut candidates: Vec<_> = bank().iter().collect();
    candidates.sort_by_key(|q| (excluded.contains(&q.id.as_str()), random.hash_one(&q.id)));
    let mut topics = HashSet::new();
    // `take` stops the iterator, so topics are only claimed for picked questions.
    let mut picked: Vec<_> = candidates
        .iter()
        .copied()
        .filter(|q| preferred.contains(&q.topic.as_str()) && topics.insert(q.topic.as_str()))
        .take(count / 2)
        .collect();
    let rest = count - picked.len();
    picked.extend(
        candidates
            .iter()
            .copied()
            .filter(|q| topics.insert(q.topic.as_str()))
            .take(rest),
    );
    picked.sort_by_key(|q| random.hash_one(&q.id));
    picked
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::chat::validate_question;

    #[test]
    fn bank_is_valid_diverse_and_has_stable_unique_ids() {
        assert_eq!(bank().len(), 66);
        let mut ids = HashSet::new();
        let mut questions = HashSet::new();
        let mut topics = std::collections::HashMap::new();
        for q in bank() {
            assert!(ids.insert(&q.id));
            assert!(questions.insert(q.question.to_lowercase()));
            assert!(
                q.id.len() <= 64 && q.id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            );
            assert_eq!(validate_question(&q.question), Ok(q.question.as_str()));
            assert!(!q.icon.is_empty() && !q.topic.is_empty());
            *topics.entry(&q.topic).or_insert(0) += 1;
        }
        assert_eq!(topics.len(), 11);
        assert!(topics.values().all(|count| *count == 6));
    }

    #[test]
    fn rotation_excludes_recent_questions_and_keeps_four_topics() {
        let mut recent: Vec<String> = Vec::new();
        for _ in 0..100 {
            let excluded: Vec<_> = recent.iter().map(String::as_str).collect();
            let batch = select(&excluded, 4, &[]);
            assert_eq!(batch.len(), 4);
            assert_eq!(
                batch.iter().map(|q| &q.topic).collect::<HashSet<_>>().len(),
                4
            );
            assert!(batch.iter().all(|q| !recent.contains(&q.id)));
            recent.extend(batch.iter().map(|q| q.id.clone()));
            if recent.len() > RECENT_LIMIT {
                recent.drain(..recent.len() - RECENT_LIMIT);
            }
        }
    }

    #[test]
    fn six_sparks_come_from_six_topics() {
        let mut recent: Vec<String> = Vec::new();
        for _ in 0..100 {
            let excluded: Vec<_> = recent.iter().map(String::as_str).collect();
            let batch = select(&excluded, 6, &[]);
            assert_eq!(batch.len(), 6);
            let topics: HashSet<_> = batch.iter().map(|q| &q.topic).collect();
            assert_eq!(topics.len(), 6);
            recent.extend(batch.iter().map(|q| q.id.clone()));
            if recent.len() > RECENT_LIMIT {
                recent.drain(..recent.len() - RECENT_LIMIT);
            }
        }
    }

    #[test]
    fn up_to_half_the_sparks_come_from_preferred_topics() {
        for _ in 0..100 {
            let batch = select(&[], 4, &["Body", "Plants", "Light"]);
            let preferred = batch
                .iter()
                .filter(|q| ["Body", "Plants", "Light"].contains(&q.topic.as_str()))
                .count();
            assert!(preferred >= 2, "at least half from preferred topics");
            assert_eq!(
                batch.iter().map(|q| &q.topic).collect::<HashSet<_>>().len(),
                4
            );
            let one = select(&[], 6, &["Body"]);
            assert!(one.iter().any(|q| q.topic == "Body"));
            assert_eq!(one.len(), 6);
        }
        // Preferring every topic changes nothing about size or variety.
        let every: Vec<_> = bank().iter().map(|q| q.topic.as_str()).collect();
        assert_eq!(select(&[], 6, &every).len(), 6);
    }

    #[test]
    fn exhausted_exclusions_still_produce_a_full_batch() {
        let all: Vec<_> = bank().iter().map(|q| q.id.as_str()).collect();
        for count in COUNTS {
            assert_eq!(select(&all, count, &[]).len(), count);
        }
    }
}
