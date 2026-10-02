import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../math/horizon_ffi.dart' as rust;

/// Full-screen celebration overlay for large wins.
///
/// The tier is determined by the multiplier of the win vs. the bet:
///   - BIG WIN     x10..x24
///   - MEGA WIN    x25..x74
///   - EPIC WIN    x75..x149
///   - LEGENDARY!  x150+
///
/// The amount counts up from 0 to the final value with a satisfying
/// deceleration, framed by a radial burst of golden particles.
class BigWinOverlay extends StatefulWidget {
  const BigWinOverlay({
    super.key,
    required this.amount,
    required this.multiplier,
    required this.onDone,
  });

  final int amount;
  final int multiplier;
  final VoidCallback onDone;

  /// Returns null if the win doesn't qualify as a Big Win.
  ///
  /// The actual tier thresholds live in Rust (`hx_big_win_tier`) so the
  /// multiplier cutoffs are not visible as plaintext integers in the
  /// Dart snapshot. Dart only owns the display strings per tier.
  static String? tierFor(int multiplier) {
    if (multiplier < 0) return null;
    final int tier = rust.hxBigWinTier(multiplier);
    switch (tier) {
      case 3:
        return 'LEGENDARY WIN';
      case 2:
        return 'EPIC WIN';
      case 1:
        return 'MEGA WIN';
      case 0:
        return 'BIG WIN';
      default:
        return null;
    }
  }

  @override
  State<BigWinOverlay> createState() => _BigWinOverlayState();
}

class _BigWinOverlayState extends State<BigWinOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _counter;
  late final AnimationController _burst;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _counter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _counter.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? tier = BigWinOverlay.tierFor(widget.multiplier);
    if (tier == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        if (_finished) widget.onDone();
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Container(color: Colors.black.withValues(alpha: 0.72)),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (BuildContext context, _) => CustomPaint(
                painter: _BurstPainter(t: _burst.value),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _TierTitle(text: tier),
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: _counter,
                  builder: (BuildContext context, _) {
                    final double t =
                        Curves.easeOutCubic.transform(_counter.value);
                    final int shown = (widget.amount * t).round();
                    if (_counter.isCompleted && !_finished) {
                      _finished = true;
                    }
                    return Text(
                      '$shown',
                      style: TextStyle(
                        color: const Color(0xFFFFE082),
                        fontSize: 74,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        shadows: <Shadow>[
                          Shadow(
                            blurRadius: 40,
                            color:
                                const Color(0xFFFFB300).withValues(alpha: 0.95),
                          ),
                          const Shadow(blurRadius: 6, color: Colors.black),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'FUN COINS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'x${widget.multiplier} YOUR BET',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    shadows: <Shadow>[
                      Shadow(
                        blurRadius: 16,
                        color: const Color(0xFF00BFFF).withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _counter,
                  builder: (BuildContext context, _) => AnimatedOpacity(
                    opacity: _counter.value > 0.85 ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: const Text(
                      'TAP TO CONTINUE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierTitle extends StatefulWidget {
  const _TierTitle({required this.text});
  final String text;
  @override
  State<_TierTitle> createState() => _TierTitleState();
}

class _TierTitleState extends State<_TierTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (BuildContext context, _) {
        final double t = Curves.easeOutBack.transform(_pop.value);
        return Transform.scale(
          scale: 0.4 + t * 0.7,
          child: Text(
            widget.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              shadows: <Shadow>[
                Shadow(
                  blurRadius: 30,
                  color: const Color(0xFFFFC107).withValues(alpha: 0.95),
                ),
                const Shadow(blurRadius: 8, color: Colors.black),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    const int rays = 12;
    for (int i = 0; i < rays; i++) {
      final double angle = (i / rays) * math.pi * 2 + t * math.pi * 2;
      final Paint p = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFFFC107).withValues(alpha: 0.7),
            const Color(0x00FFC107),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: size.width));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final Path ray = Path()
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.6, -18)
        ..lineTo(size.width * 0.6, 18)
        ..close();
      canvas.drawPath(ray, p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}
