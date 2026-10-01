//! Per-caller and whole-server limits on model questions, independent of HTTP.
//!
//! The server is reachable from the internet, so one caller must not be able to
//! keep the model busy all day. Counting is in memory only: a restart forgets it.

use std::{
    collections::HashMap,
    net::IpAddr,
    sync::Mutex,
    time::{Duration, Instant},
};

const MINUTE: Duration = Duration::from_secs(60);
const DAY: Duration = Duration::from_secs(24 * 60 * 60);
/// Above this many remembered callers, finished day windows are dropped.
const PRUNE_ABOVE: usize = 10_000;

/// How many questions are allowed; `0` switches that limit off.
#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub per_minute: u32,
    pub per_day: u32,
    /// All callers together, per day.
    pub daily_cap: u32,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            per_minute: 10,
            per_day: 200,
            daily_cap: 1_000,
        }
    }
}

/// Which limit refused a question.
#[derive(Debug, PartialEq, Eq)]
pub enum Refusal {
    Minute,
    Day,
    DailyCap,
}

impl Refusal {
    pub fn message(&self) -> &'static str {
        match self {
            Self::Minute => "That was a lot of questions! Take a short break and try again.",
            Self::Day => "You have asked lots of questions today. Come back tomorrow!",
            Self::DailyCap => "The science tutor has answered a lot today. Come back tomorrow!",
        }
    }
}

/// A count that starts again once `length` has passed since its first question.
#[derive(Clone, Copy)]
struct Window {
    started: Instant,
    count: u32,
}

impl Window {
    fn new(now: Instant) -> Self {
        Self {
            started: now,
            count: 0,
        }
    }

    fn refresh(&mut self, now: Instant, length: Duration) {
        if now.duration_since(self.started) >= length {
            *self = Self::new(now);
        }
    }

    /// Seconds until this window starts again, at least one.
    fn wait(&self, now: Instant, length: Duration) -> u64 {
        length
            .saturating_sub(now.duration_since(self.started))
            .as_secs()
            .max(1)
    }
}

struct Caller {
    minute: Window,
    day: Window,
}

struct Counts {
    callers: HashMap<IpAddr, Caller>,
    everyone: Window,
}

pub struct Limiter {
    limits: Limits,
    // A std Mutex is enough: it is held only for the few lines below, never
    // across an `.await`.
    counts: Mutex<Counts>,
}

impl Limiter {
    pub fn new(limits: Limits) -> Self {
        Self {
            limits,
            counts: Mutex::new(Counts {
                callers: HashMap::new(),
                everyone: Window::new(Instant::now()),
            }),
        }
    }

    /// Count one question from `ip`, or refuse it with the seconds to wait.
    /// Refused questions are not counted.
    pub fn check(&self, ip: IpAddr, now: Instant) -> Result<(), (Refusal, u64)> {
        let limits = self.limits;
        let mut counts = self.counts.lock().unwrap_or_else(|e| e.into_inner());
        counts.everyone.refresh(now, DAY);
        if limits.daily_cap > 0 && counts.everyone.count >= limits.daily_cap {
            return Err((Refusal::DailyCap, counts.everyone.wait(now, DAY)));
        }
        if counts.callers.len() >= PRUNE_ABOVE {
            counts
                .callers
                .retain(|_, caller| now.duration_since(caller.day.started) < DAY);
        }
        let caller = counts.callers.entry(caller_key(ip)).or_insert(Caller {
            minute: Window::new(now),
            day: Window::new(now),
        });
        caller.minute.refresh(now, MINUTE);
        caller.day.refresh(now, DAY);
        if limits.per_day > 0 && caller.day.count >= limits.per_day {
            return Err((Refusal::Day, caller.day.wait(now, DAY)));
        }
        if limits.per_minute > 0 && caller.minute.count >= limits.per_minute {
            return Err((Refusal::Minute, caller.minute.wait(now, MINUTE)));
        }
        caller.minute.count += 1;
        caller.day.count += 1;
        counts.everyone.count += 1;
        Ok(())
    }
}

/// One IPv6 customer usually owns a whole /64 (2^64 addresses), so IPv6
/// callers are counted by their first 64 bits. IPv4 addresses are used whole.
fn caller_key(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V4(_) => ip,
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => {
                let mut bytes = v6.octets();
                bytes[8..].fill(0);
                IpAddr::from(bytes)
            }
        },
    }
}
