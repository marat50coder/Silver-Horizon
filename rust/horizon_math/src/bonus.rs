// Bonus wheel: 3/4/5-scatter prize tables + weighted pick.

use crate::obfs::{dec16, enc16};
use crate::rng::with_rng;
use crate::sync_cell::IsolateCell;

/// Sentinel multiplier for a FREE SPINS wedge. Matches the Dart constant.
pub const FREE_SPINS_MARKER: i32 = -1;
pub const FREE_SPINS_COUNT: i32 = 10;
pub const WHEEL_SLICES: usize = 8;

// Row = scatter tier (0=3-scatter, 1=4-scatter mega, 2=5-scatter grand).
// Values are stored as scrambled i16 so the "100 / 250 Grand" numbers
// do not appear in the __DATA strings dump.

const fn enc_i16(v: i16, i: usize) -> i16 {
    enc16(v as u16, i) as i16
}

fn dec_i16(raw: i16, i: usize) -> i16 {
    dec16(raw as u16, i) as i16
}

const TABLE: [[i16; WHEEL_SLICES]; 3] = [
    [
        enc_i16(2, 0),
        enc_i16(5, 1),
        enc_i16(10, 2),
        enc_i16(3, 3),
        enc_i16(20, 4),
        enc_i16(4, 5),
        enc_i16(50, 6),
        enc_i16(8, 7),
    ],
    [
        enc_i16(10, 8),
        enc_i16(20, 9),
        enc_i16(35, 10),
        enc_i16(FREE_SPINS_MARKER as i16, 11),
        enc_i16(60, 12),
        enc_i16(25, 13),
        enc_i16(100, 14),
        enc_i16(40, 15),
    ],
    [
        enc_i16(25, 16),
        enc_i16(40, 17),
        enc_i16(75, 18),
        enc_i16(FREE_SPINS_MARKER as i16, 19),
        enc_i16(120, 20),
        enc_i16(50, 21),
        enc_i16(250, 22),
        enc_i16(80, 23),
    ],
];

const WEIGHTS_MEGA: [u8; WHEEL_SLICES] = [10, 12, 12, 14, 8, 12, 5, 11];

fn tier_for(scatter_count: u32) -> usize {
    if scatter_count >= 5 {
        2
    } else if scatter_count >= 4 {
        1
    } else {
        0
    }
}

#[inline(never)]
pub fn multiplier(scatter_count: u32, slice: usize) -> i32 {
    let tier = tier_for(scatter_count);
    let flat_idx = tier * WHEEL_SLICES + slice;
    dec_i16(TABLE[tier][slice], flat_idx) as i32
}

/// `true` if the slice at `slice` is the FREE SPINS wedge for this tier.
#[inline(always)]
pub fn is_free_slice(scatter_count: u32, slice: usize) -> bool {
    multiplier(scatter_count, slice) == FREE_SPINS_MARKER
}

#[inline(never)]
pub fn pick_slice(scatter_count: u32) -> usize {
    let tier = tier_for(scatter_count);
    if tier == 0 {
        return with_rng(|rng| rng.next_bounded(WHEEL_SLICES as u32) as usize);
    }
    let mut total: u32 = 0;
    let mut i = 0;
    while i < WHEEL_SLICES {
        total += WEIGHTS_MEGA[i] as u32;
        i += 1;
    }
    let mut roll = with_rng(|rng| rng.next_bounded(total)) as i64;
    let mut i = 0;
    while i < WHEEL_SLICES {
        roll -= WEIGHTS_MEGA[i] as i64;
        if roll < 0 {
            return i;
        }
        i += 1;
    }
    0
}

#[derive(Copy, Clone)]
pub struct BonusResult {
    pub slice: u32,
    pub coins: u32,
    pub free_spins: u32,
}

const EMPTY: BonusResult = BonusResult {
    slice: 0,
    coins: 0,
    free_spins: 0,
};
static LAST: IsolateCell<BonusResult> = IsolateCell::new(EMPTY);

#[inline(never)]
pub fn roll_bonus(scatter_count: u32, bet: u32) -> BonusResult {
    let slice = pick_slice(scatter_count);
    let mult = multiplier(scatter_count, slice);
    let result = if mult == FREE_SPINS_MARKER {
        BonusResult {
            slice: slice as u32,
            coins: 0,
            free_spins: FREE_SPINS_COUNT as u32,
        }
    } else {
        BonusResult {
            slice: slice as u32,
            coins: (mult.max(0) as u32).saturating_mul(bet),
            free_spins: 0,
        }
    };
    *LAST.get() = result;
    result
}

#[inline(always)]
pub fn last_result() -> BonusResult {
    *LAST.get()
}
