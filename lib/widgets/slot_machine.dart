import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../math/horizon_ffi.dart' as rust;
import '../models/payline.dart';
import '../models/slot_symbol.dart';
import 'payline_overlay.dart';

/// Result returned by [SlotMachineState.spin].
class SpinResult {
  const SpinResult({
    required this.lineWin,
    required this.scatterCount,
    required this.scatterPositions,
  });

  /// Total payout for line wins.
  final int lineWin;

  /// Number of scatter tiles that landed on the grid. 3+ triggers a bonus.
  final int scatterCount;

  /// Grid positions (column, row) of every scatter on the final grid.
  final List<(int, int)> scatterPositions;
}

/// A 5-reel × 3-row slot machine rendered inside the frame asset.
///
/// The reels spin with smoothly decelerating motion. Each reel receives a
/// slightly different target time so they stop one after another, which is
/// the standard "one, two, three, four, five" reveal feel of a real slot.
class SlotMachine extends StatefulWidget {
  const SlotMachine({super.key});

  @override
  State<SlotMachine> createState() => SlotMachineState();
}

class SlotMachineState extends State<SlotMachine>
    with TickerProviderStateMixin {
  static const int reelCount = 5;
  static const int rowCount = 3;

  /// Symbols currently visible in each reel column (top → bottom).
  late List<List<SlotSymbol>> _visible;

  /// Controllers per reel that drive the strip position.
  late List<AnimationController> _controllers;

  /// Strip contents per reel. The strip is a long list of symbols; the reel
  /// scrolls up through it and stops so that the last three items are visible.
  late List<List<SlotSymbol>> _strips;

  /// Line-wins currently being highlighted on the grid.
  List<LineWin> _winningLines = <LineWin>[];

  /// Which cells are part of any winning line (for glow pulse).
  Set<(int, int)> _winningCells = <(int, int)>{};

  /// When multiple lines win, we cycle through them one at a time to keep the
  /// visualization readable. This index picks the currently displayed line.
  int _highlightIndex = 0;
  Timer? _highlightTimer;

  /// Reels currently in "anticipation" (golden slow-spin) mode.
  final Set<int> _anticipatingReels = <int>{};

  /// Positions of the scatters currently visible on the finished grid; used
  /// to draw the "scatter connect" animation before the bonus triggers.
  List<(int, int)> _scatterHighlight = <(int, int)>[];
  bool _showScatterConnect = false;

  @override
  void initState() {
    super.initState();

    _visible = List<List<SlotSymbol>>.generate(
      reelCount,
      (_) => List<SlotSymbol>.generate(rowCount, (_) => _pickWeighted()),
    );

    _controllers = List<AnimationController>.generate(
      reelCount,
      (_) => AnimationController(vsync: this),
    );

    _strips = List<List<SlotSymbol>>.generate(reelCount, (_) => <SlotSymbol>[]);
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    for (final AnimationController c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Weighted single-symbol draw. Thin wrapper over the Rust pick so the
  /// visual spin-blur filler uses the same distribution as the real reels.
  SlotSymbol _pickWeighted() => SlotSymbol.fromIndex(rust.hxPickWeighted());

  /// Spin all reels and return line win + scatter data.
  Future<SpinResult> spin({required int bet}) async {
    _clearHighlights();
    _anticipatingReels.clear();
    _scatterHighlight = <(int, int)>[];
    _showScatterConnect = false;

    // All math (grid generation with the at-most-one-scatter-per-reel
    // cap AND payline evaluation) runs in the Rust `horizon_math`
    // static library. We just read back the resulting grid + line wins
    // + scatter list via cheap integer FFI calls.
    rust.hxSpin(bet);

    final List<List<SlotSymbol>> finalGrid = List<List<SlotSymbol>>.generate(
      reelCount,
      (int c) => List<SlotSymbol>.generate(
        rowCount,
        (int r) => SlotSymbol.fromIndex(rust.hxLastGridAt(c, r)),
      ),
    );

    // Scatter positions decoded from Rust's packed (col<<8 | row).
    final int scatterCount = rust.hxLastScatterCount();
    final List<(int, int)> finalScatters = <(int, int)>[
      for (int i = 0; i < scatterCount; i++)
        _unpackScatter(rust.hxLastScatterPacked(i)),
    ];
    final List<bool> reelHasScatter = <bool>[
      for (int c = 0; c < reelCount; c++)
        finalScatters.any(((int, int) p) => p.$1 == c),
    ];

    // Build strips per reel: [current visible + filler + final]. The
    // filler is purely cosmetic ("blur" during the spin animation); we
    // still draw it from the Rust weighted pick so the running symbols
    // match the real distribution. Scatters are filtered out on reels
    // that already end with a scatter so the eye never sees two on a
    // single column during the slow-stop.
    const int fillerLength = 24;
    for (int col = 0; col < reelCount; col++) {
      final bool colHasScatter = reelHasScatter[col];
      final List<SlotSymbol> strip = <SlotSymbol>[];
      strip.addAll(_visible[col]);
      for (int i = 0; i < fillerLength; i++) {
        SlotSymbol s = _pickWeighted();
        if (s.isScatter && colHasScatter) {
          s = SlotSymbol.cherry;
        }
        strip.add(s);
      }
      strip.addAll(finalGrid[col]);
      _strips[col] = strip;
    }

    // Hold every reel on the start of its strip (current visible symbols)
    // so waiting columns stay frozen until their own turn.
    for (int col = 0; col < reelCount; col++) {
      _controllers[col].value = 0;
    }

    // Last "normal" reel: after the player has seen 2 scatters, remaining
    // reels switch to golden slow-zoom, one at a time.
    int pivot = reelCount - 1;
    int seen = 0;
    for (int c = 0; c < reelCount; c++) {
      if (reelHasScatter[c]) seen++;
      if (seen == 2 && c < reelCount - 1) {
        pivot = c;
        break;
      }
    }

    if (!mounted) return _cancelledSpin;

    // Regular cascade: reel N kicks off while reel N-1 is in its landing
    // (end of the animation), so they never all start together.
    final List<Future<void>> cascade = <Future<void>>[];
    for (int col = 0; col <= pivot; col++) {
      if (col > 0) {
        await _waitUntilProgress(_controllers[col - 1], 0.34);
        if (!mounted) return _cancelledSpin;
      }
      cascade.add(
        _animateReel(
          col,
          finalSymbols: finalGrid[col],
          durationMs: 560,
          anticipating: false,
        ),
      );
    }
    await Future.wait<void>(cascade);
    if (!mounted) return _cancelledSpin;

    bool bonusHit = false;
    for (int col = pivot + 1; col < reelCount; col++) {
      final bool anticipating = !bonusHit;
      await _animateReel(
        col,
        finalSymbols: finalGrid[col],
        durationMs: anticipating ? 1800 : 480,
        anticipating: anticipating,
      );
      if (!mounted) return _cancelledSpin;
      if (reelHasScatter[col]) bonusHit = true;
    }
    if (mounted) setState(() => _anticipatingReels.clear());

    // If 3+ scatters landed, play the "connect" animation before returning.
    if (finalScatters.length >= 3 && mounted) {
      setState(() {
        _scatterHighlight = finalScatters;
        _showScatterConnect = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return _cancelledSpin;
      setState(() => _showScatterConnect = false);
    }

    // Payline evaluation already ran inside `hx_spin`. Read the resulting
    // line-wins back out of Rust-owned storage via dedicated accessors.
    final int lineCount = rust.hxLastLineCount();
    final List<LineWin> wins = <LineWin>[
      for (int i = 0; i < lineCount; i++)
        LineWin(
          paylineIndex: rust.hxLastLinePayline(i),
          symbol: SlotSymbol.fromIndex(rust.hxLastLineSymbol(i)),
          matchCount: rust.hxLastLineMatchCount(i),
          amount: rust.hxLastLineAmount(i),
        ),
    ];
    final int total = rust.hxLastTotal();
    final Set<(int, int)> cells = <(int, int)>{};
    for (final LineWin w in wins) {
      for (int c = 0; c < w.matchCount; c++) {
        cells.add((c, w.payline.rows[c]));
      }
    }

    if (wins.isNotEmpty) {
      setState(() {
        _winningLines = wins;
        _winningCells = cells;
        _highlightIndex = 0;
      });
      if (wins.length > 1) {
        _highlightTimer = Timer.periodic(const Duration(milliseconds: 900),
            (Timer t) {
          if (!mounted) return;
          setState(() {
            _highlightIndex = (_highlightIndex + 1) % _winningLines.length;
          });
        });
      }
    }

    return SpinResult(
      lineWin: total,
      scatterCount: finalScatters.length,
      scatterPositions: finalScatters,
    );
  }

  static const SpinResult _cancelledSpin = SpinResult(
    lineWin: 0,
    scatterCount: 0,
    scatterPositions: <(int, int)>[],
  );

  /// Runs one reel from strip start to the pre-chosen final symbols.
  Future<void> _animateReel(
    int col, {
    required List<SlotSymbol> finalSymbols,
    required int durationMs,
    required bool anticipating,
  }) async {
    final AnimationController c = _controllers[col];
    c.duration = Duration(milliseconds: durationMs);
    c.value = 0;
    if (mounted) {
      setState(() {
        if (anticipating) {
          _anticipatingReels
            ..clear()
            ..add(col);
        } else {
          _anticipatingReels.remove(col);
        }
      });
    }
    await c.forward().orCancel.catchError((Object _) {});
    if (!mounted) return;
    setState(() {
      _visible[col] = List<SlotSymbol>.from(finalSymbols);
      _anticipatingReels.remove(col);
    });
  }

  /// Resolves when [controller] has advanced to [threshold] (0–1 of duration).
  Future<void> _waitUntilProgress(
    AnimationController controller,
    double threshold,
  ) async {
    if (controller.value >= threshold ||
        controller.status == AnimationStatus.completed) {
      return;
    }
    final Completer<void> done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }
    void listener() {
      if (controller.value >= threshold ||
          controller.status == AnimationStatus.completed) {
        controller.removeListener(listener);
        finish();
      }
    }
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        controller.removeStatusListener(onStatus);
        controller.removeListener(listener);
        finish();
      }
    }
    controller.addListener(listener);
    controller.addStatusListener(onStatus);
    await done.future;
    controller.removeListener(listener);
    controller.removeStatusListener(onStatus);
  }

  /// Decodes Rust's (col<<8 | row) packed scatter position.
  (int, int) _unpackScatter(int packed) => (packed >> 8, packed & 0xFF);

  /// Number of winning lines from the most recent spin.
  int get winCount => _winningLines.length;

  /// Clears highlight state (called by the parent after showing the win
  /// popup, or before a new spin).
  void clearHighlights() => _clearHighlights();

  void _clearHighlights() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    if (!mounted) {
      _winningLines = <LineWin>[];
      _winningCells = <(int, int)>{};
      return;
    }
    setState(() {
      _winningLines = <LineWin>[];
      _winningCells = <(int, int)>{};
      _highlightIndex = 0;
    });
  }

  // Note: payline evaluation lives in `rust/horizon_math/src/slot.rs`
  // (`evaluate_lines`). The old Dart `_evaluate` method was removed
  // during the math migration — reach it through `rust.hxSpin` +
  // `rust.hxLastLine*` queries.

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Slot frame asset is 2138×1283 → aspect ~1.666.
        const double aspect = 2138 / 1283;
        double frameWidth = constraints.maxWidth;
        double frameHeight = frameWidth / aspect;
        if (frameHeight > constraints.maxHeight) {
          frameHeight = constraints.maxHeight;
          frameWidth = frameHeight * aspect;
        }

        // Playfield insets measured pixel-precisely from the frame asset
        // (2138×1283). The first cyan divider inside the frame sits at x=245
        // (11.46%) and the last at x=1872 (right inset = 12.44%); vertical
        // dividers at y=176 (13.72%) and y=1101 (bottom inset = 14.19%).
        // Using these exact ratios makes every symbol drop dead-center inside
        // its visible cell on every reel.
        const double gridLeftPct = 245 / 2138;
        const double gridRightPct = (2138 - 1872) / 2138;
        const double gridTopPct = 176 / 1283;
        const double gridBottomPct = (1283 - 1101) / 1283;

        final double gridWidth =
            frameWidth * (1 - gridLeftPct - gridRightPct);
        final double gridHeight =
            frameHeight * (1 - gridTopPct - gridBottomPct);
        final double gridLeft = frameWidth * gridLeftPct;
        final double gridTop = frameHeight * gridTopPct;

        final double cellWidth = gridWidth / reelCount;
        final double cellHeight = gridHeight / rowCount;

        final LineWin? activeLine = _winningLines.isEmpty
            ? null
            : _winningLines[_highlightIndex % _winningLines.length];

        return SizedBox(
          width: frameWidth,
          height: frameHeight,
          child: Stack(
            children: <Widget>[
              // Frame first (below).
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(
                    'assets/Silver_Horizon_gameplay_assets/slot_frame_asset.webp',
                    fit: BoxFit.fill,
                  ),
                ),
              ),

              // Reels on top of the frame's inner grid.
              Positioned(
                left: gridLeft,
                top: gridTop,
                width: gridWidth,
                height: gridHeight,
                child: Row(
                  children: List<Widget>.generate(reelCount, (int col) {
                    return SizedBox(
                      width: cellWidth,
                      child: _Reel(
                        controller: _controllers[col],
                        strip: _strips[col],
                        currentVisible: _visible[col],
                        cellWidth: cellWidth,
                        cellHeight: cellHeight,
                        anticipating: _anticipatingReels.contains(col),
                        highlightRows: <int>{
                          for (final (int c, int r) in _winningCells)
                            if (c == col) r
                        },
                      ),
                    );
                  }),
                ),
              ),

              // Payline overlay for the currently-active winning line.
              if (activeLine != null)
                Positioned(
                  left: gridLeft,
                  top: gridTop,
                  width: gridWidth,
                  height: gridHeight,
                  child: IgnorePointer(
                    child: PaylineOverlay(
                      payline: activeLine.payline,
                      matchCount: activeLine.matchCount,
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                    ),
                  ),
                ),

              // Scatter-connect burst: draws bright golden beams between the
              // 3+ scatters that just landed, right before the bonus opens.
              if (_showScatterConnect && _scatterHighlight.length >= 3)
                Positioned(
                  left: gridLeft,
                  top: gridTop,
                  width: gridWidth,
                  height: gridHeight,
                  child: IgnorePointer(
                    child: ScatterConnectOverlay(
                      positions: _scatterHighlight,
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Reel extends StatelessWidget {
  const _Reel({
    required this.controller,
    required this.strip,
    required this.currentVisible,
    required this.cellWidth,
    required this.cellHeight,
    required this.highlightRows,
    this.anticipating = false,
  });

  final AnimationController controller;
  final List<SlotSymbol> strip;
  final List<SlotSymbol> currentVisible;
  final double cellWidth;
  final double cellHeight;
  final Set<int> highlightRows;
  final bool anticipating;

  @override
  Widget build(BuildContext context) {
    final Widget reelBody = ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, _) {
          if (strip.isEmpty || controller.duration == null) {
            return _StaticColumn(
              symbols: currentVisible,
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              highlightRows: highlightRows,
            );
          }

          final int startIndex = 0;
          final int endIndex = strip.length - 3;
          // Anticipation reels use a much gentler easing so the spin reads
          // as "slow and dramatic" instead of a fast whip stop.
          final Curve curve = anticipating
              ? Curves.easeInOutCubic
              : Curves.easeOutQuint;
          final double t = curve.transform(controller.value);
          final double indexPos =
              startIndex + (endIndex - startIndex) * t;

          final int topIndex = indexPos.floor();
          final double fraction = indexPos - topIndex;

          final List<Widget> tiles = <Widget>[];
          for (int i = 0; i < 4; i++) {
            final int idx = topIndex + i;
            if (idx < 0 || idx >= strip.length) continue;
            tiles.add(Positioned(
              left: 0,
              right: 0,
              top: (i - fraction) * cellHeight,
              height: cellHeight,
              child: _SymbolCell(
                symbol: strip[idx],
                cellWidth: cellWidth,
                cellHeight: cellHeight,
              ),
            ));
          }

          return SizedBox(
            height: cellHeight * 3,
            child: Stack(children: tiles),
          );
        },
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // Golden anticipation glow behind the reel + a subtle scale-up zoom
        // so the "chosen" reel visually pops while it slow-spins.
        if (anticipating)
          Positioned.fill(
            child: IgnorePointer(child: _AnticipationGlow()),
          ),
        if (anticipating)
          AnimatedScale(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            scale: 1.06,
            child: reelBody,
          )
        else
          AnimatedScale(
            duration: const Duration(milliseconds: 220),
            scale: 1.0,
            child: reelBody,
          ),
      ],
    );
  }
}

/// Pulsing warm-gold overlay used to visually mark reels that are in the
/// "hoping for the 3rd scatter" anticipation phase.
class _AnticipationGlow extends StatefulWidget {
  @override
  State<_AnticipationGlow> createState() => _AnticipationGlowState();
}

class _AnticipationGlowState extends State<_AnticipationGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        final double t = _c.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.9,
              colors: <Color>[
                const Color(0xFFFFD54F).withValues(alpha: 0.28 + 0.22 * t),
                const Color(0xFFFFB300).withValues(alpha: 0.18 + 0.12 * t),
                Colors.transparent,
              ],
              stops: const <double>[0.0, 0.55, 1.0],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFFC107).withValues(alpha: 0.5 + 0.4 * t),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StaticColumn extends StatelessWidget {
  const _StaticColumn({
    required this.symbols,
    required this.cellWidth,
    required this.cellHeight,
    required this.highlightRows,
  });
  final List<SlotSymbol> symbols;
  final double cellWidth;
  final double cellHeight;
  final Set<int> highlightRows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: cellHeight * symbols.length,
      child: Stack(
        children: <Widget>[
          for (int row = 0; row < symbols.length; row++)
            Positioned(
              left: 0,
              right: 0,
              top: row * cellHeight,
              height: cellHeight,
              child: _SymbolCell(
                symbol: symbols[row],
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                highlighted: highlightRows.contains(row),
              ),
            ),
        ],
      ),
    );
  }
}

class _SymbolCell extends StatefulWidget {
  const _SymbolCell({
    required this.symbol,
    required this.cellWidth,
    required this.cellHeight,
    this.highlighted = false,
  });
  final SlotSymbol symbol;
  final double cellWidth;
  final double cellHeight;
  final bool highlighted;

  @override
  State<_SymbolCell> createState() => _SymbolCellState();
}

class _SymbolCellState extends State<_SymbolCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _updatePulse();
  }

  @override
  void didUpdateWidget(covariant _SymbolCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted != oldWidget.highlighted) _updatePulse();
  }

  void _updatePulse() {
    if (widget.highlighted) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The symbol is drawn inside a square sized to the SMALLER of the cell's
    // width/height, with generous padding on all four sides so it always sits
    // safely inside the visible cell — no matter whether the surrounding
    // frame cell is a bit narrower on the outer columns.
    final double side = math.min(widget.cellWidth, widget.cellHeight);
    final double pad = side * 0.14;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (BuildContext context, Widget? child) {
        final double glow = widget.highlighted ? (0.4 + 0.6 * _pulse.value) : 0;
        final double scale = widget.highlighted ? (1 + 0.06 * _pulse.value) : 1;
        return Center(
          child: SizedBox(
            width: widget.cellWidth,
            height: widget.cellHeight,
            child: Center(
              child: SizedBox.square(
                dimension: side - pad * 2,
                child: Transform.scale(
                  scale: scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(side * 0.12),
                      boxShadow: glow > 0
                          ? <BoxShadow>[
                              BoxShadow(
                                color: const Color(0xFFFFC107)
                                    .withValues(alpha: glow),
                                blurRadius: 22,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Image.asset(
        widget.symbol.assetPath,
        fit: BoxFit.contain,
        alignment: Alignment.center,
      ),
    );
  }
}
