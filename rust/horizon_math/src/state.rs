// Indexed access to every persistent number (wallet, stats, free spins,
// daily bonus, achievements) so Dart can save and restore progress.
//
// Keeps the crate's FFI rule: plain integers in and out, no blobs. Dart
// walks indices 0..field_count() and stores the values itself.
//
// Index order is a storage contract: only ever append new fields.

use crate::ach::{self, ACH_COUNT};
use crate::profile;

const PROFILE_FIELDS: u32 = 15;

pub fn field_count() -> u32 {
    PROFILE_FIELDS + 2 * ACH_COUNT as u32
}

pub fn get(idx: u32) -> i64 {
    let p = profile::get();
    match idx {
        0 => p.coins,
        1 => p.total_spins as i64,
        2 => p.paid_spins as i64,
        3 => p.free_spins_played as i64,
        4 => p.total_wagered as i64,
        5 => p.total_won as i64,
        6 => p.biggest_win as i64,
        7 => p.biggest_mult as i64,
        8 => p.bonus_rounds as i64,
        9 => p.win_streak as i64,
        10 => p.longest_win_streak as i64,
        11 => p.free_spins_remaining as i64,
        12 => p.free_spins_bet as i64,
        13 => p.daily_streak as i64,
        14 => p.last_daily_claim_unix_s,
        _ => {
            let rel = idx - PROFILE_FIELDS;
            let id = (rel / 2) as usize;
            match ach::get(id) {
                Some(a) if rel % 2 == 0 => a.progress as i64,
                Some(a) => a.claimed as i64,
                None => 0,
            }
        }
    }
}

#[inline(always)]
fn u64_of(v: i64) -> u64 {
    if v < 0 {
        0
    } else {
        v as u64
    }
}

#[inline(always)]
fn u32_of(v: i64) -> u32 {
    u64_of(v).min(u32::MAX as u64) as u32
}

pub fn set(idx: u32, v: i64) {
    let p = profile::get();
    match idx {
        0 => p.coins = v.max(0),
        1 => p.total_spins = u64_of(v),
        2 => p.paid_spins = u64_of(v),
        3 => p.free_spins_played = u64_of(v),
        4 => p.total_wagered = u64_of(v),
        5 => p.total_won = u64_of(v),
        6 => p.biggest_win = u64_of(v),
        7 => p.biggest_mult = u32_of(v),
        8 => p.bonus_rounds = u32_of(v),
        9 => p.win_streak = u32_of(v),
        10 => p.longest_win_streak = u32_of(v),
        11 => p.free_spins_remaining = u32_of(v),
        12 => p.free_spins_bet = u32_of(v),
        13 => p.daily_streak = u32_of(v) % profile::daily_table_len(),
        14 => p.last_daily_claim_unix_s = v.max(0),
        _ => {
            let rel = idx - PROFILE_FIELDS;
            let id = (rel / 2) as usize;
            if let Some(a) = ach::get(id) {
                if rel % 2 == 0 {
                    a.progress = u32_of(v).min(a.target);
                } else {
                    a.claimed = v != 0;
                }
            }
        }
    }
}
