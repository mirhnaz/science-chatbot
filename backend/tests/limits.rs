use curio_server::limits::{Limiter, Limits, Refusal};
use std::{
    net::IpAddr,
    time::{Duration, Instant},
};

fn ip(text: &str) -> IpAddr {
    text.parse().unwrap()
}

fn limiter(per_minute: u32, per_day: u32, daily_cap: u32) -> Limiter {
    Limiter::new(Limits {
        per_minute,
        per_day,
        daily_cap,
    })
}

#[test]
fn minute_limit_is_per_caller_and_resets_after_a_minute() {
    let limiter = limiter(2, 0, 0);
    let start = Instant::now();
    let caller = ip("203.0.113.7");
    assert_eq!(limiter.check(caller, start), Ok(()));
    assert_eq!(limiter.check(caller, start), Ok(()));
    let later = start + Duration::from_secs(20);
    assert_eq!(limiter.check(caller, later), Err((Refusal::Minute, 40)));
    assert_eq!(limiter.check(ip("203.0.113.8"), later), Ok(()));
    let next_minute = start + Duration::from_secs(60);
    assert_eq!(limiter.check(caller, next_minute), Ok(()));
}

#[test]
fn day_limit_outlasts_the_minute_window() {
    let limiter = limiter(0, 2, 0);
    let start = Instant::now();
    let caller = ip("203.0.113.7");
    assert_eq!(limiter.check(caller, start), Ok(()));
    assert_eq!(limiter.check(caller, start), Ok(()));
    let hour = start + Duration::from_secs(3600);
    assert_eq!(limiter.check(caller, hour), Err((Refusal::Day, 23 * 3600)));
    let tomorrow = start + Duration::from_secs(24 * 3600);
    assert_eq!(limiter.check(caller, tomorrow), Ok(()));
}

#[test]
fn daily_cap_covers_all_callers_and_refusals_are_not_counted() {
    let limiter = limiter(1, 0, 2);
    let start = Instant::now();
    assert_eq!(limiter.check(ip("203.0.113.1"), start), Ok(()));
    // Refused by the minute limit, so it does not use up the cap.
    assert!(limiter.check(ip("203.0.113.1"), start).is_err());
    assert_eq!(limiter.check(ip("203.0.113.2"), start), Ok(()));
    // The whole-server day began when the limiter was made, just before `start`.
    let refused = limiter.check(ip("203.0.113.3"), start).unwrap_err();
    assert_eq!(refused.0, Refusal::DailyCap);
    assert!(refused.1 > 23 * 3600 && refused.1 <= 24 * 3600);
}

#[test]
fn ipv6_callers_are_counted_by_their_64_bit_network() {
    let limiter = limiter(1, 0, 0);
    let start = Instant::now();
    assert_eq!(limiter.check(ip("2001:db8:1:2::1"), start), Ok(()));
    assert!(limiter.check(ip("2001:db8:1:2:ffff::9"), start).is_err());
    assert_eq!(limiter.check(ip("2001:db8:1:3::1"), start), Ok(()));
    // An IPv4 address written in IPv6 form is the same caller as plain IPv4.
    assert_eq!(limiter.check(ip("::ffff:203.0.113.7"), start), Ok(()));
    assert!(limiter.check(ip("203.0.113.7"), start).is_err());
}

#[test]
fn zero_switches_every_limit_off() {
    let limiter = limiter(0, 0, 0);
    let start = Instant::now();
    for _ in 0..500 {
        assert_eq!(limiter.check(ip("203.0.113.7"), start), Ok(()));
    }
}
