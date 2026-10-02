// Big-win tiers. Matches `BigWinOverlay.tierFor`:
//   x10..x24  → 0 BIG
//   x25..x74  → 1 MEGA
//   x75..x149 → 2 EPIC
//   x150+     → 3 LEGENDARY
//
// Returns -1 for "no celebration".

use crate::obfs::{dec16, enc16};

const THRESHOLDS: [u16; 4] = [enc16(10, 0), enc16(25, 1), enc16(75, 2), enc16(150, 3)];

#[inline(never)]
pub fn tier(multiplier: u32) -> i32 {
    let mut i = (THRESHOLDS.len() as isize) - 1;
    while i >= 0 {
        let t = dec16(THRESHOLDS[i as usize], i as usize) as u32;
        if multiplier >= t {
            return i as i32;
        }
        i -= 1;
    }
    -1
}
