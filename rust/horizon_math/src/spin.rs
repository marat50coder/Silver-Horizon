// Spin orchestrator: holds the result of the most recent `hx_spin` so the
// Dart side can query the grid, line wins and scatter positions through
// cheap integer accessors without crossing the FFI boundary with pointers
// to Rust-owned heap buffers.

use crate::rng::with_rng;
use crate::slot::{evaluate_lines, generate_grid, scatter_positions, LineWin, GRID_CELLS};
use crate::sync_cell::IsolateCell;

pub struct Spin {
    pub grid: [u8; GRID_CELLS],
    pub wins: Vec<LineWin>,
    pub scatters: Vec<u16>,
    pub total: u32,
}

impl Spin {
    const fn empty() -> Self {
        Self {
            grid: [0; GRID_CELLS],
            wins: Vec::new(),
            scatters: Vec::new(),
            total: 0,
        }
    }
}

static LAST: IsolateCell<Spin> = IsolateCell::new(Spin::empty());

#[inline(always)]
pub fn last() -> &'static mut Spin {
    LAST.get()
}

#[inline(never)]
pub fn roll(bet: u32) -> u32 {
    let s = LAST.get();
    with_rng(|rng| generate_grid(rng, &mut s.grid));
    s.wins = evaluate_lines(&s.grid, bet);
    scatter_positions(&s.grid, &mut s.scatters);
    s.total = s.wins.iter().map(|w| w.amount).sum();
    s.total
}
