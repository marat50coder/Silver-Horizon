// Slot symbols: weighted picks + per-count payout tables.
//
// Index order MUST match the Dart `SlotSymbol` enum declaration order:
//   0 cherry, 1 grape, 2 watermelon, 3 clever, 4 bell, 5 bar, 6 star,
//   7 diamond, 8 crown, 9 wild, 10 scatter.
//
// Only the integer tables live here. Asset paths, colors, display names
// stay in Dart — nothing in this crate ever touches a string.

use crate::obfs::{dec16, dec8, enc16, enc8};
use crate::rng::Pcg32;

pub const SYMBOL_COUNT: usize = 11;

pub const CHERRY: u8 = 0;
pub const GRAPE: u8 = 1;
pub const WATERMELON: u8 = 2;
pub const CLEVER: u8 = 3;
pub const BELL: u8 = 4;
pub const BAR: u8 = 5;
pub const STAR: u8 = 6;
pub const DIAMOND: u8 = 7;
pub const CROWN: u8 = 8;
pub const WILD: u8 = 9;
pub const SCATTER: u8 = 10;

// Scrambled weights (de-obfs via `mask8(i)`): raw plaintext values match
// the Dart source — 22, 20, 18, 15, 13, 11, 9, 7, 5, 4, 3.
const WEIGHTS: [u8; SYMBOL_COUNT] = [
    enc8(22, 0),
    enc8(20, 1),
    enc8(18, 2),
    enc8(15, 3),
    enc8(13, 4),
    enc8(11, 5),
    enc8(9, 6),
    enc8(7, 7),
    enc8(5, 8),
    enc8(4, 9),
    enc8(3, 10),
];

// Flat pay-table of 11 symbols × 6 counts (0..=5), stored as scrambled
// u16 so a hex dump of __DATA does not reveal the "1,3,8" / "8,25,80"
// pattern that signals a line-pay slot. Index = symbol_id * 6 + count.
const PAY_LEN: usize = SYMBOL_COUNT * 6;

const fn pay_slot(sym: u8, count: usize, value: u16) -> (usize, u16) {
    let i = sym as usize * 6 + count;
    (i, enc16(value, i))
}

const fn build_pay_table() -> [u16; PAY_LEN] {
    let mut out = [0u16; PAY_LEN];
    let mut i = 0;
    // Zero every slot (with its mask applied), THEN overwrite the
    // paying rows. This keeps unused rows looking like noise rather
    // than a run of literal zeros.
    while i < PAY_LEN {
        out[i] = enc16(0, i);
        i += 1;
    }
    let entries: [(u8, usize, u16); 24] = [
        (CHERRY, 3, 1),
        (CHERRY, 4, 3),
        (CHERRY, 5, 8),
        (GRAPE, 3, 1),
        (GRAPE, 4, 4),
        (GRAPE, 5, 10),
        (WATERMELON, 3, 2),
        (WATERMELON, 4, 5),
        (WATERMELON, 5, 14),
        (CLEVER, 3, 2),
        (CLEVER, 4, 6),
        (CLEVER, 5, 18),
        (BELL, 3, 3),
        (BELL, 4, 8),
        (BELL, 5, 25),
        (STAR, 3, 4),
        (STAR, 4, 12),
        (STAR, 5, 35),
        (DIAMOND, 3, 5),
        (DIAMOND, 4, 18),
        (DIAMOND, 5, 50),
        (CROWN, 3, 8),
        (CROWN, 4, 25),
        (CROWN, 5, 80),
        // BAR, WILD, SCATTER: no line payout of their own.
    ];
    let mut j = 0;
    while j < entries.len() {
        let (sym, count, value) = entries[j];
        let (idx, enc) = pay_slot(sym, count, value);
        out[idx] = enc;
        j += 1;
    }
    out
}

const PAY_TABLE: [u16; PAY_LEN] = build_pay_table();

#[inline(never)]
pub fn weight(sym: u8) -> u32 {
    let i = sym as usize;
    dec8(WEIGHTS[i], i) as u32
}

#[inline(never)]
pub fn payout(sym: u8, count: u8) -> u32 {
    if sym as usize >= SYMBOL_COUNT || count >= 6 {
        return 0;
    }
    let i = sym as usize * 6 + count as usize;
    dec16(PAY_TABLE[i], i) as u32
}

#[inline(always)]
pub fn is_scatter(sym: u8) -> bool {
    sym == SCATTER
}

#[inline(always)]
pub fn is_wild(sym: u8) -> bool {
    sym == WILD || sym == BAR
}

/// Weighted pick across the full 11-symbol strip, matching the Dart
/// `_randomSymbol` behaviour (fallback to cherry on an under-roll — only
/// reachable if the weight table is edited to all zeros).
#[inline(never)]
pub fn pick_weighted(rng: &mut Pcg32) -> u8 {
    let mut total: u32 = 0;
    let mut i = 0;
    while i < SYMBOL_COUNT {
        total += weight(i as u8);
        i += 1;
    }
    if total == 0 {
        return CHERRY;
    }
    let mut r = rng.next_bounded(total) as i64;
    let mut i = 0;
    while i < SYMBOL_COUNT {
        r -= weight(i as u8) as i64;
        if r < 0 {
            return i as u8;
        }
        i += 1;
    }
    CHERRY
}

/// Pick from the "paying" subset (no wilds, no scatter) — used by the
/// scatter-cap enforcement to replace a second scatter on a reel.
#[inline(never)]
pub fn pick_paying(rng: &mut Pcg32) -> u8 {
    const PAYING: [u8; 7] = [CHERRY, GRAPE, WATERMELON, CLEVER, BELL, STAR, DIAMOND];
    let idx = rng.next_bounded(PAYING.len() as u32) as usize;
    PAYING[idx]
}
