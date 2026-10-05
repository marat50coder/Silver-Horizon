// Player wallet + session statistics + daily bonus cooldown + free-spin
// mode. Dart owns `ChangeNotifier` notification and saving to disk (via the
// indexed accessors in `state.rs`); this crate just owns the numbers.

use crate::ach;
use crate::obfs::{dec16, enc16};
use crate::sync_cell::IsolateCell;

pub const FREE_SPIN_MULT: u32 = 2;
pub const DAILY_COOLDOWN_HOURS: i64 = 20;

// Daily reward table, scrambled.
const DAILY_LEN: usize = 7;
const DAILY: [u16; DAILY_LEN] = [
    enc16(250, 0),
    enc16(500, 1),
    enc16(750, 2),
    enc16(1000, 3),
    enc16(1500, 4),
    enc16(2000, 5),
    enc16(5000, 6),
];

#[inline(always)]
pub const fn daily_table_len() -> u32 {
    DAILY_LEN as u32
}

#[inline(always)]
pub fn daily_reward(streak: u32) -> u32 {
    let idx = (streak as usize).min(DAILY_LEN - 1);
    dec16(DAILY[idx], idx) as u32
}

#[derive(Copy, Clone)]
pub struct Profile {
    pub coins: i64,

    pub total_spins: u64,
    pub paid_spins: u64,
    pub free_spins_played: u64,
    pub total_wagered: u64,
    pub total_won: u64,
    pub biggest_win: u64,
    pub biggest_mult: u32,
    pub bonus_rounds: u32,
    pub win_streak: u32,
    pub longest_win_streak: u32,

    pub free_spins_remaining: u32,
    pub free_spins_bet: u32,

    pub daily_streak: u32,
    pub last_daily_claim_unix_s: i64, // 0 if never claimed
}

const INITIAL: Profile = Profile {
    coins: 1000,
    total_spins: 0,
    paid_spins: 0,
    free_spins_played: 0,
    total_wagered: 0,
    total_won: 0,
    biggest_win: 0,
    biggest_mult: 0,
    bonus_rounds: 0,
    win_streak: 0,
    longest_win_streak: 0,
    free_spins_remaining: 0,
    free_spins_bet: 0,
    daily_streak: 0,
    last_daily_claim_unix_s: 0,
};

static STATE: IsolateCell<Profile> = IsolateCell::new(INITIAL);

#[inline(always)]
pub fn get() -> &'static mut Profile {
    STATE.get()
}

#[inline(never)]
pub fn add_coins(amount: i64) {
    if amount <= 0 {
        return;
    }
    let p = get();
    p.coins = p.coins.saturating_add(amount);
}

#[inline(never)]
pub fn spend_coins(amount: i64) -> bool {
    if amount <= 0 {
        return true;
    }
    let p = get();
    if p.coins < amount {
        return false;
    }
    p.coins -= amount;
    true
}

#[inline(never)]
pub fn record_spin(bet: i64, win: i64, was_free: bool) {
    let p = get();
    p.total_spins += 1;
    if was_free {
        p.free_spins_played += 1;
    } else {
        p.paid_spins += 1;
        if bet > 0 {
            p.total_wagered = p.total_wagered.saturating_add(bet as u64);
        }
    }
    if win > 0 {
        p.total_won = p.total_won.saturating_add(win as u64);
        if (win as u64) > p.biggest_win {
            p.biggest_win = win as u64;
        }
        let mult: u32 = if bet > 0 {
            (win as u64 / bet as u64) as u32
        } else {
            0
        };
        if mult > p.biggest_mult {
            p.biggest_mult = mult;
        }
        p.win_streak = p.win_streak.saturating_add(1);
        if p.win_streak > p.longest_win_streak {
            p.longest_win_streak = p.win_streak;
        }
    } else {
        p.win_streak = 0;
    }
    ach::on_spin(bet, win, p.longest_win_streak);
}

#[inline(never)]
pub fn record_bonus_triggered(scatters: u32) {
    let p = get();
    p.bonus_rounds = p.bonus_rounds.saturating_add(1);
    ach::on_bonus_triggered(scatters);
}

#[inline(never)]
pub fn record_bonus_prize(amount: i64) {
    if amount <= 0 {
        return;
    }
    let p = get();
    p.total_won = p.total_won.saturating_add(amount as u64);
    if (amount as u64) > p.biggest_win {
        p.biggest_win = amount as u64;
    }
    ach::on_bonus_win(amount);
}

/// Returns 1000 × RTP%, as integer, or 0 when nothing has been wagered.
#[inline(always)]
pub fn rtp_x1000() -> u64 {
    let p = get();
    if p.total_wagered == 0 {
        return 0;
    }
    (p.total_won.saturating_mul(100_000)) / p.total_wagered
}

// --- free spins ---

#[inline(never)]
pub fn grant_free_spins(count: u32, bet: u32) {
    let p = get();
    p.free_spins_remaining = p.free_spins_remaining.saturating_add(count);
    p.free_spins_bet = bet;
}

/// Returns the bet to use for this free spin (0 if none remained).
#[inline(never)]
pub fn consume_free_spin() -> u32 {
    let p = get();
    if p.free_spins_remaining == 0 {
        return 0;
    }
    p.free_spins_remaining -= 1;
    let bet = p.free_spins_bet;
    if p.free_spins_remaining == 0 {
        p.free_spins_bet = 0;
    }
    bet
}

// --- daily bonus ---

#[inline(always)]
pub fn can_claim_daily(now_unix_s: i64) -> bool {
    let p = get();
    if p.last_daily_claim_unix_s == 0 {
        return true;
    }
    (now_unix_s - p.last_daily_claim_unix_s) >= DAILY_COOLDOWN_HOURS * 3600
}

#[inline(always)]
pub fn next_daily_reward() -> u32 {
    daily_reward(get().daily_streak)
}

#[inline(always)]
pub fn time_until_claim_s(now_unix_s: i64) -> i64 {
    let p = get();
    if p.last_daily_claim_unix_s == 0 {
        return 0;
    }
    let next = p.last_daily_claim_unix_s + DAILY_COOLDOWN_HOURS * 3600;
    let left = next - now_unix_s;
    if left < 0 {
        0
    } else {
        left
    }
}

/// Returns the amount granted, or 0 if still on cooldown.
#[inline(never)]
pub fn claim_daily(now_unix_s: i64) -> u32 {
    if !can_claim_daily(now_unix_s) {
        return 0;
    }
    let p = get();
    let reward = daily_reward(p.daily_streak);
    p.coins = p.coins.saturating_add(reward as i64);
    p.last_daily_claim_unix_s = now_unix_s;
    p.daily_streak = (p.daily_streak + 1) % (DAILY_LEN as u32);
    ach::on_daily_claim();
    reward
}
