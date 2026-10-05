// C-ABI entry points consumed by `lib/math/bindings.dart` (via
// `dart:ffi`) and referenced by `ios/Runner/RustGlue.swift` to keep the
// linker from dead-stripping them in release builds.
//
// Only plain integers cross the boundary. The caller writes a `bet` and
// calls `hx_spin`; the result (grid + line wins + scatters + total) is
// cached inside the Rust crate and then read back through dedicated
// query functions. This keeps the ABI narrow enough to pack into a
// single Dart binding file.

use crate::ach;
use crate::bigwin;
use crate::bonus;
use crate::paylines;
use crate::profile;
use crate::spin;
use crate::state;
use crate::symbols;

// -------- meta --------

#[no_mangle]
pub extern "C" fn hx_version() -> u32 {
    1
}

// -------- symbols --------

#[no_mangle]
pub extern "C" fn hx_symbol_count() -> u32 {
    symbols::SYMBOL_COUNT as u32
}

#[no_mangle]
pub extern "C" fn hx_symbol_is_scatter(sym: u8) -> u8 {
    symbols::is_scatter(sym) as u8
}

#[no_mangle]
pub extern "C" fn hx_symbol_is_wild(sym: u8) -> u8 {
    symbols::is_wild(sym) as u8
}

#[no_mangle]
pub extern "C" fn hx_symbol_payout(sym: u8, count: u8) -> u32 {
    symbols::payout(sym, count)
}

/// Weighted draw across the full 11-symbol strip. Used by the reel
/// animation to fill the "spin blur" positions with symbols that match
/// the real distribution — purely cosmetic (the final visible grid comes
/// from `hx_spin`).
#[no_mangle]
pub extern "C" fn hx_pick_weighted() -> u8 {
    crate::rng::with_rng(|rng| symbols::pick_weighted(rng))
}

// -------- paylines --------

#[no_mangle]
pub extern "C" fn hx_payline_count() -> u32 {
    paylines::PAYLINE_COUNT as u32
}

#[no_mangle]
pub extern "C" fn hx_payline_row(line_idx: u32, col: u32) -> u8 {
    if (line_idx as usize) >= paylines::PAYLINE_COUNT || (col as usize) >= paylines::REELS {
        return 0;
    }
    paylines::row_of(line_idx as usize, col as usize)
}

// -------- spin --------

/// Rolls a fresh grid, evaluates lines, caches scatter positions.
/// Returns the total line win for this spin.
#[no_mangle]
pub extern "C" fn hx_spin(bet: u32) -> u32 {
    spin::roll(bet)
}

#[no_mangle]
pub extern "C" fn hx_last_grid_at(col: u32, row: u32) -> u8 {
    if (col as usize) >= paylines::REELS || (row as usize) >= paylines::ROWS {
        return 0;
    }
    let s = spin::last();
    s.grid[(col as usize) * paylines::ROWS + row as usize]
}

#[no_mangle]
pub extern "C" fn hx_last_line_count() -> u32 {
    spin::last().wins.len() as u32
}

#[no_mangle]
pub extern "C" fn hx_last_line_payline(idx: u32) -> u8 {
    let w = &spin::last().wins;
    if (idx as usize) >= w.len() {
        return 0;
    }
    w[idx as usize].payline_index
}

#[no_mangle]
pub extern "C" fn hx_last_line_symbol(idx: u32) -> u8 {
    let w = &spin::last().wins;
    if (idx as usize) >= w.len() {
        return 0;
    }
    w[idx as usize].symbol
}

#[no_mangle]
pub extern "C" fn hx_last_line_match_count(idx: u32) -> u8 {
    let w = &spin::last().wins;
    if (idx as usize) >= w.len() {
        return 0;
    }
    w[idx as usize].match_count
}

#[no_mangle]
pub extern "C" fn hx_last_line_amount(idx: u32) -> u32 {
    let w = &spin::last().wins;
    if (idx as usize) >= w.len() {
        return 0;
    }
    w[idx as usize].amount
}

#[no_mangle]
pub extern "C" fn hx_last_scatter_count() -> u32 {
    spin::last().scatters.len() as u32
}

/// Returns the scatter position at `idx` packed as `(col << 8) | row`.
#[no_mangle]
pub extern "C" fn hx_last_scatter_packed(idx: u32) -> u16 {
    let s = &spin::last().scatters;
    if (idx as usize) >= s.len() {
        return 0;
    }
    s[idx as usize]
}

#[no_mangle]
pub extern "C" fn hx_last_total() -> u32 {
    spin::last().total
}

// -------- bonus --------

#[no_mangle]
pub extern "C" fn hx_bonus_slice_count() -> u32 {
    bonus::WHEEL_SLICES as u32
}

#[no_mangle]
pub extern "C" fn hx_bonus_free_spins_marker() -> i32 {
    bonus::FREE_SPINS_MARKER
}

#[no_mangle]
pub extern "C" fn hx_bonus_multiplier(scatter_count: u32, slice: u32) -> i32 {
    if (slice as usize) >= bonus::WHEEL_SLICES {
        return 0;
    }
    bonus::multiplier(scatter_count, slice as usize)
}

#[no_mangle]
pub extern "C" fn hx_bonus_is_free_slice(scatter_count: u32, slice: u32) -> u8 {
    if (slice as usize) >= bonus::WHEEL_SLICES {
        return 0;
    }
    bonus::is_free_slice(scatter_count, slice as usize) as u8
}

/// Rolls the wheel. Returns the slice index that landed under the arrow.
/// Use `hx_bonus_last_coins` / `hx_bonus_last_free_spins` to read the
/// resolved prize.
#[no_mangle]
pub extern "C" fn hx_bonus_roll(scatter_count: u32, bet: u32) -> u32 {
    let r = bonus::roll_bonus(scatter_count, bet);
    r.slice
}

#[no_mangle]
pub extern "C" fn hx_bonus_last_coins() -> u32 {
    bonus::last_result().coins
}

#[no_mangle]
pub extern "C" fn hx_bonus_last_free_spins() -> u32 {
    bonus::last_result().free_spins
}

// -------- big win --------

#[no_mangle]
pub extern "C" fn hx_big_win_tier(multiplier: u32) -> i32 {
    bigwin::tier(multiplier)
}

// -------- profile: wallet --------

#[no_mangle]
pub extern "C" fn hx_profile_coins() -> i64 {
    profile::get().coins
}

#[no_mangle]
pub extern "C" fn hx_profile_add_coins(amount: i64) {
    profile::add_coins(amount);
}

#[no_mangle]
pub extern "C" fn hx_profile_spend_coins(amount: i64) -> u8 {
    profile::spend_coins(amount) as u8
}

// -------- profile: stats --------

#[no_mangle]
pub extern "C" fn hx_profile_record_spin(bet: i64, win: i64, was_free: u8) {
    profile::record_spin(bet, win, was_free != 0);
}

#[no_mangle]
pub extern "C" fn hx_profile_record_bonus_triggered(scatters: u32) {
    profile::record_bonus_triggered(scatters);
}

#[no_mangle]
pub extern "C" fn hx_profile_record_bonus_prize(amount: i64) {
    profile::record_bonus_prize(amount);
}

#[no_mangle]
pub extern "C" fn hx_profile_total_spins() -> u64 {
    profile::get().total_spins
}

#[no_mangle]
pub extern "C" fn hx_profile_paid_spins() -> u64 {
    profile::get().paid_spins
}

#[no_mangle]
pub extern "C" fn hx_profile_free_spins_played() -> u64 {
    profile::get().free_spins_played
}

#[no_mangle]
pub extern "C" fn hx_profile_total_wagered() -> u64 {
    profile::get().total_wagered
}

#[no_mangle]
pub extern "C" fn hx_profile_total_won() -> u64 {
    profile::get().total_won
}

#[no_mangle]
pub extern "C" fn hx_profile_biggest_win() -> u64 {
    profile::get().biggest_win
}

#[no_mangle]
pub extern "C" fn hx_profile_biggest_mult() -> u32 {
    profile::get().biggest_mult
}

#[no_mangle]
pub extern "C" fn hx_profile_bonus_rounds() -> u32 {
    profile::get().bonus_rounds
}

#[no_mangle]
pub extern "C" fn hx_profile_longest_win_streak() -> u32 {
    profile::get().longest_win_streak
}

#[no_mangle]
pub extern "C" fn hx_profile_rtp_x1000() -> u64 {
    profile::rtp_x1000()
}

// -------- profile: free spins --------

#[no_mangle]
pub extern "C" fn hx_profile_grant_free_spins(count: u32, bet: u32) {
    profile::grant_free_spins(count, bet);
}

#[no_mangle]
pub extern "C" fn hx_profile_consume_free_spin() -> u32 {
    profile::consume_free_spin()
}

#[no_mangle]
pub extern "C" fn hx_profile_free_spins_remaining() -> u32 {
    profile::get().free_spins_remaining
}

#[no_mangle]
pub extern "C" fn hx_profile_free_spins_bet() -> u32 {
    profile::get().free_spins_bet
}

#[no_mangle]
pub extern "C" fn hx_profile_in_free_mode() -> u8 {
    (profile::get().free_spins_remaining > 0) as u8
}

#[no_mangle]
pub extern "C" fn hx_profile_free_spin_mult() -> u32 {
    profile::FREE_SPIN_MULT
}

// -------- profile: daily --------

#[no_mangle]
pub extern "C" fn hx_profile_can_claim_daily(now_unix_s: i64) -> u8 {
    profile::can_claim_daily(now_unix_s) as u8
}

#[no_mangle]
pub extern "C" fn hx_profile_daily_streak() -> u32 {
    profile::get().daily_streak
}

#[no_mangle]
pub extern "C" fn hx_profile_next_daily_reward() -> u32 {
    profile::next_daily_reward()
}

#[no_mangle]
pub extern "C" fn hx_profile_daily_reward_at(streak: u32) -> u32 {
    profile::daily_reward(streak)
}

#[no_mangle]
pub extern "C" fn hx_profile_daily_table_len() -> u32 {
    profile::daily_table_len()
}

#[no_mangle]
pub extern "C" fn hx_profile_time_until_claim_s(now_unix_s: i64) -> i64 {
    profile::time_until_claim_s(now_unix_s)
}

#[no_mangle]
pub extern "C" fn hx_profile_claim_daily(now_unix_s: i64) -> u32 {
    profile::claim_daily(now_unix_s)
}

// -------- achievements --------

#[no_mangle]
pub extern "C" fn hx_ach_count() -> u32 {
    ach::ACH_COUNT as u32
}

#[no_mangle]
pub extern "C" fn hx_ach_target(id: u32) -> u32 {
    ach::get(id as usize).map(|a| a.target).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn hx_ach_reward(id: u32) -> u32 {
    ach::get(id as usize).map(|a| a.reward).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn hx_ach_progress(id: u32) -> u32 {
    ach::get(id as usize).map(|a| a.progress).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn hx_ach_claimed(id: u32) -> u8 {
    ach::get(id as usize)
        .map(|a| a.claimed as u8)
        .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn hx_ach_completed_count() -> u32 {
    ach::completed_count()
}

#[no_mangle]
pub extern "C" fn hx_ach_claimable_count() -> u32 {
    ach::claimable_count()
}

#[no_mangle]
pub extern "C" fn hx_ach_claim(id: u32) -> u32 {
    ach::claim(id as usize)
}

// ----- saved progress (indexed, see state.rs) -----

#[no_mangle]
pub extern "C" fn hx_state_field_count() -> u32 {
    state::field_count()
}

#[no_mangle]
pub extern "C" fn hx_state_get(idx: u32) -> i64 {
    state::get(idx)
}

#[no_mangle]
pub extern "C" fn hx_state_set(idx: u32, value: i64) {
    state::set(idx, value)
}
