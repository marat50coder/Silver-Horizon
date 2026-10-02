// 10 paylines across a 5-reel × 3-row grid. Row per column (0=top,
// 1=middle, 2=bottom). Shape matches the Dart `kPaylines` so the overlay
// renderer and the evaluator agree on which cells are "on the line".

pub const PAYLINE_COUNT: usize = 10;
pub const REELS: usize = 5;
pub const ROWS: usize = 3;

const RAW: [[u8; REELS]; PAYLINE_COUNT] = [
    [1, 1, 1, 1, 1], // middle
    [0, 0, 0, 0, 0], // top
    [2, 2, 2, 2, 2], // bottom
    [0, 1, 2, 1, 0], // V
    [2, 1, 0, 1, 2], // ^
    [0, 0, 1, 2, 2], // step down
    [2, 2, 1, 0, 0], // step up
    [1, 0, 1, 2, 1], // zig
    [1, 2, 1, 0, 1], // zag
    [0, 1, 1, 1, 0], // wave
];

#[inline(always)]
pub fn row_of(line: usize, col: usize) -> u8 {
    RAW[line][col]
}
