// Grid generation + payline evaluation.

use crate::paylines::{row_of, PAYLINE_COUNT, REELS, ROWS};
use crate::rng::Pcg32;
use crate::symbols::{is_scatter, is_wild, payout, pick_paying, pick_weighted, SCATTER, WILD};

pub const GRID_CELLS: usize = REELS * ROWS;

#[inline(always)]
pub fn grid_index(col: usize, row: usize) -> usize {
    col * ROWS + row
}

/// Fills `grid` (len = REELS*ROWS) with a fresh weighted draw and
/// enforces at most one scatter per reel column.
#[inline(never)]
pub fn generate_grid(rng: &mut Pcg32, grid: &mut [u8; GRID_CELLS]) {
    let mut col = 0;
    while col < REELS {
        let mut row = 0;
        while row < ROWS {
            grid[grid_index(col, row)] = pick_weighted(rng);
            row += 1;
        }
        col += 1;
    }
    limit_scatters_per_reel(rng, grid);
}

#[inline(never)]
fn limit_scatters_per_reel(rng: &mut Pcg32, grid: &mut [u8; GRID_CELLS]) {
    let mut col = 0;
    while col < REELS {
        let mut seen = false;
        let mut row = 0;
        while row < ROWS {
            let i = grid_index(col, row);
            if is_scatter(grid[i]) {
                if seen {
                    grid[i] = pick_paying(rng);
                } else {
                    seen = true;
                }
            }
            row += 1;
        }
        col += 1;
    }
}

#[derive(Copy, Clone)]
pub struct LineWin {
    pub payline_index: u8,
    pub symbol: u8,
    pub match_count: u8,
    pub amount: u32,
}

#[inline(never)]
pub fn evaluate_lines(grid: &[u8; GRID_CELLS], bet: u32) -> Vec<LineWin> {
    let mut out: Vec<LineWin> = Vec::with_capacity(PAYLINE_COUNT);

    let mut p = 0;
    while p < PAYLINE_COUNT {
        let mut line_syms = [0u8; REELS];
        let mut c = 0;
        while c < REELS {
            let r = row_of(p, c) as usize;
            line_syms[c] = grid[grid_index(c, r)];
            c += 1;
        }

        // Scatter never pays on a line.
        if is_scatter(line_syms[0]) {
            p += 1;
            continue;
        }

        // Base symbol = first non-wild from the left (before any scatter
        // break). All-wild runs still count via the wild payout fallback.
        let mut base: Option<u8> = None;
        let mut k = 0;
        while k < REELS {
            let s = line_syms[k];
            if is_scatter(s) {
                break;
            }
            if !is_wild(s) {
                base = Some(s);
                break;
            }
            k += 1;
        }

        let mut match_count: u8 = 0;
        let mut c = 0;
        while c < REELS {
            let s = line_syms[c];
            if is_scatter(s) {
                break;
            }
            match base {
                None => {
                    if is_wild(s) {
                        match_count += 1;
                    } else {
                        break;
                    }
                }
                Some(b) => {
                    if s == b || is_wild(s) {
                        match_count += 1;
                    } else {
                        break;
                    }
                }
            }
            c += 1;
        }

        if match_count >= 3 {
            let pay_symbol = base.unwrap_or(WILD);
            let amount = payout(pay_symbol, match_count) * bet;
            if amount > 0 {
                out.push(LineWin {
                    payline_index: p as u8,
                    symbol: pay_symbol,
                    match_count,
                    amount,
                });
            }
        }

        p += 1;
    }

    out
}

/// Positions of scatter cells, packed as (col << 8) | row.
pub fn scatter_positions(grid: &[u8; GRID_CELLS], out: &mut Vec<u16>) {
    out.clear();
    let mut col = 0;
    while col < REELS {
        let mut row = 0;
        while row < ROWS {
            if grid[grid_index(col, row)] == SCATTER {
                out.push(((col as u16) << 8) | row as u16);
            }
            row += 1;
        }
        col += 1;
    }
}
