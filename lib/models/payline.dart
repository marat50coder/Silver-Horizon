import 'dart:ui' show Color;

import 'slot_symbol.dart';

/// A payline is a per-column list of row indices (0=top, 1=middle, 2=bottom)
/// that traces a shape across the 5-reel × 3-row grid.
///
/// The `rows` arrays are purely geometric overlay metadata — the game-math
/// payline rows live in `rust/horizon_math/src/paylines.rs` and must stay
/// numerically identical to the arrays below. The evaluation itself is run
/// by Rust (`hx_spin`), so this file is "renderer only".
class Payline {
  const Payline({
    required this.name,
    required this.rows,
    required this.color,
  });

  final String name;
  final List<int> rows;
  final Color color;

  /// Symbol grid coordinates for this payline: [(col, row), ...].
  Iterable<(int, int)> positions() sync* {
    for (int c = 0; c < rows.length; c++) {
      yield (c, rows[c]);
    }
  }
}

/// The 10 paylines used by Silver Horizon.
///
/// Colors are chosen to be visually distinct so multiple simultaneous wins
/// can be told apart when overlaid on the reels. `rows` arrays MUST match
/// `rust/horizon_math/src/paylines.rs::RAW` cell for cell.
const List<Payline> kPaylines = <Payline>[
  Payline(
    name: 'Line 1',
    rows: <int>[1, 1, 1, 1, 1],
    color: Color(0xFFFF3B30),
  ),
  Payline(
    name: 'Line 2',
    rows: <int>[0, 0, 0, 0, 0],
    color: Color(0xFF00E5FF),
  ),
  Payline(
    name: 'Line 3',
    rows: <int>[2, 2, 2, 2, 2],
    color: Color(0xFFFFEB3B),
  ),
  Payline(
    name: 'Line 4',
    rows: <int>[0, 1, 2, 1, 0],
    color: Color(0xFF7CFF6B),
  ),
  Payline(
    name: 'Line 5',
    rows: <int>[2, 1, 0, 1, 2],
    color: Color(0xFFFF80AB),
  ),
  Payline(
    name: 'Line 6',
    rows: <int>[0, 0, 1, 2, 2],
    color: Color(0xFFFFA726),
  ),
  Payline(
    name: 'Line 7',
    rows: <int>[2, 2, 1, 0, 0],
    color: Color(0xFFB388FF),
  ),
  Payline(
    name: 'Line 8',
    rows: <int>[1, 0, 1, 2, 1],
    color: Color(0xFF00BFA5),
  ),
  Payline(
    name: 'Line 9',
    rows: <int>[1, 2, 1, 0, 1],
    color: Color(0xFFFFD54F),
  ),
  Payline(
    name: 'Line 10',
    rows: <int>[0, 1, 1, 1, 0],
    color: Color(0xFFE040FB),
  ),
];

/// Result for a single winning line. Rust returns one of these per line
/// win via `hx_last_line_*` queries after `hx_spin`.
class LineWin {
  const LineWin({
    required this.paylineIndex,
    required this.symbol,
    required this.matchCount,
    required this.amount,
  });

  final int paylineIndex;
  final SlotSymbol symbol;
  final int matchCount;
  final int amount;

  Payline get payline => kPaylines[paylineIndex];
}
