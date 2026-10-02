// Achievements: progress + claim.
//
// Dart owns the display strings (title / description) because they are
// user-facing and need localization in the future. This crate owns
// progress counters and the claim machinery — everything that's "math".

use crate::profile;
use crate::sync_cell::IsolateCell;

pub const ACH_COUNT: usize = 8;

pub const FIRST_STEPS: usize = 0;
pub const SEASONED: usize = 1;
pub const BIG_HITTER: usize = 2;
pub const MEGA_HITTER: usize = 3;
pub const BONUS_HUNTER: usize = 4;
pub const MEGA_BONUS: usize = 5;
pub const HOT_STREAK: usize = 6;
pub const DAILY_DEVOTION: usize = 7;

pub struct Achievement {
    pub target: u32,
    pub reward: u32,
    pub progress: u32,
    pub claimed: bool,
}

const fn ach(target: u32, reward: u32) -> Achievement {
    Achievement {
        target,
        reward,
        progress: 0,
        claimed: false,
    }
}

static LIST: IsolateCell<[Achievement; ACH_COUNT]> = IsolateCell::new([
    ach(10, 200),
    ach(100, 1500),
    ach(1, 500),
    ach(1, 2500),
    ach(3, 1000),
    ach(1, 2000),
    ach(5, 800),
    ach(3, 750),
]);

#[inline(always)]
pub fn get(id: usize) -> Option<&'static mut Achievement> {
    if id >= ACH_COUNT {
        None
    } else {
        Some(&mut LIST.get()[id])
    }
}

fn add(id: usize, amount: u32) {
    if let Some(a) = get(id) {
        if a.claimed {
            return;
        }
        let next = a.progress.saturating_add(amount);
        a.progress = next.min(a.target);
    }
}

fn set_to(id: usize, value: u32) {
    if let Some(a) = get(id) {
        if a.claimed {
            return;
        }
        if value > a.progress {
            a.progress = value.min(a.target);
        }
    }
}

pub fn on_spin(bet: i64, win: i64, longest_streak: u32) {
    add(FIRST_STEPS, 1);
    add(SEASONED, 1);
    if bet > 0 && win >= bet.saturating_mul(10) {
        add(BIG_HITTER, 1);
    }
    if bet > 0 && win >= bet.saturating_mul(50) {
        add(MEGA_HITTER, 1);
    }
    set_to(HOT_STREAK, longest_streak);
}

pub fn on_bonus_triggered(scatters: u32) {
    add(BONUS_HUNTER, 1);
    if scatters >= 4 {
        add(MEGA_BONUS, 1);
    }
}

pub fn on_bonus_win(_amount: i64) {
    // (No specific achievement right now; mirrors the Dart hook.)
}

pub fn on_daily_claim() {
    add(DAILY_DEVOTION, 1);
}

/// Attempts to claim the reward. Returns the amount awarded, or 0 if the
/// achievement is not completed or has already been claimed.
#[inline(never)]
pub fn claim(id: usize) -> u32 {
    let a = match get(id) {
        None => return 0,
        Some(a) => a,
    };
    if a.claimed || a.progress < a.target {
        return 0;
    }
    a.claimed = true;
    let reward = a.reward;
    profile::add_coins(reward as i64);
    reward
}

pub fn completed_count() -> u32 {
    let list = LIST.get();
    let mut n = 0;
    let mut i = 0;
    while i < ACH_COUNT {
        if list[i].progress >= list[i].target {
            n += 1;
        }
        i += 1;
    }
    n
}

pub fn claimable_count() -> u32 {
    let list = LIST.get();
    let mut n = 0;
    let mut i = 0;
    while i < ACH_COUNT {
        if !list[i].claimed && list[i].progress >= list[i].target {
            n += 1;
        }
        i += 1;
    }
    n
}
