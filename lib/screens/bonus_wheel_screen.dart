import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../math/horizon_ffi.dart' as rust;
import '../widgets/app_layout.dart';

/// Result of a bonus wheel spin — either a coin prize or a free-spins award.
class BonusResult {
  const BonusResult({required this.coins, this.freeSpins = 0});
  final int coins;
  final int freeSpins;
}

/// A spinning "Wheel of Fortune"-style bonus game.
///
/// Awarded when 3+ scatters appear on the grid. The wheel has 8 prize slices,
/// each showing a multiplier applied to the triggering bet, or (for the
/// Mega / Grand wheel) a Free Spins segment. The arrow at the top marks the
/// winning slice and the result is returned to the caller.
class BonusWheelScreen extends StatefulWidget {
  const BonusWheelScreen({
    super.key,
    required this.bet,
    required this.scatterCount,
  });

  /// Bet amount that triggered the bonus (used to size prizes).
  final int bet;

  /// How many scatters landed (3/4/5). More scatters = better prize table.
  final int scatterCount;

  @override
  State<BonusWheelScreen> createState() => _BonusWheelScreenState();
}

class _BonusWheelScreenState extends State<BonusWheelScreen>
    with TickerProviderStateMixin {
  /// Free-spins sentinel: Rust owns the exact numeric value, we just mirror
  /// it so UI code can be written against a stable Dart constant. The
  /// Rust side is the source of truth for the slice prize math.
  int get _freeSpinsMarker => rust.hxBonusFreeSpinsMarker();

  late final AnimationController _spinController;
  late final AnimationController _idleController;

  bool _spinning = false;
  bool _finished = false;
  int _awardedCoins = 0;
  int _awardedFreeSpins = 0;

  double _finalRotation = 0; // in radians

  final math.Random _random = math.Random();

  bool get _mega => widget.scatterCount >= 4;

  int get _sliceCount => rust.hxBonusSliceCount();

  /// Snapshot of the slice multipliers for the current scatter tier.
  /// Only used to drive the on-wheel labels — never the prize math.
  List<int> get _multipliers {
    final int n = _sliceCount;
    return <int>[
      for (int i = 0; i < n; i++)
        rust.hxBonusMultiplier(widget.scatterCount, i),
    ];
  }

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _spinController.dispose();
    _idleController.dispose();
    super.dispose();
  }

  void _spin() {
    if (_spinning || _finished) return;

    // Rust rolls the wheel, picks the landing slice (weighted for the
    // 4/5-scatter tiers), and resolves the prize into either coins or
    // free spins. We only animate the pointer — no prize math on the
    // Dart side.
    final int target = rust.hxBonusRoll(widget.scatterCount, widget.bet);
    final int wonCoins = rust.hxBonusLastCoins();
    final int wonFreeSpins = rust.hxBonusLastFreeSpins();

    setState(() {
      _spinning = true;
    });

    final int slices = _sliceCount;
    final double sliceAngle = 2 * math.pi / slices;
    final double jitter = (_random.nextDouble() - 0.5) * sliceAngle * 0.35;
    final double baseAngle = -target * sliceAngle + jitter;
    const int extraTurns = 6;
    _finalRotation = baseAngle - extraTurns * 2 * math.pi;

    _spinController.value = 0;
    _spinController.animateTo(1.0, curve: Curves.easeOutCubic).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _spinning = false;
        _finished = true;
        _awardedCoins = wonCoins;
        _awardedFreeSpins = wonFreeSpins;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool tablet = AppLayout.isTablet(context);
    final double wheelSize =
        math.min(size.width * 0.86, tablet ? 480 : 360);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Reuse the in-game background for consistency.
          Image.asset(
            'assets/Silver_Horizon_gameplay_assets/background_game.webp',
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withValues(alpha: 0.45)),

          SafeArea(
            child: AppLayout.constrained(
              context: context,
              maxWidth: AppLayout.contentMaxWidth(context),
              child: Column(
              children: <Widget>[
                const SizedBox(height: 10),
                _BonusHeader(mega: _mega),
                const SizedBox(height: 10),
                Text(
                  _mega
                      ? '${widget.scatterCount} SCATTERS  •  MEGA PRIZES'
                      : 'Scatter Bonus  •  ${widget.scatterCount} scatters',
                  style: TextStyle(
                    color: _mega
                        ? const Color(0xFFFFE082)
                        : Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    shadows: _mega
                        ? const <Shadow>[
                            Shadow(
                              blurRadius: 12,
                              color: Color(0xFFFFB300),
                            ),
                          ]
                        : null,
                  ),
                ),
                const Spacer(),
                _WheelStack(
                  wheelSize: wheelSize,
                  slices: _multipliers.length,
                  labels: <String>[
                    for (int i = 0; i < _multipliers.length; i++)
                      _multipliers[i] == _freeSpinsMarker
                          ? 'FREE\nSPINS'
                          : 'x${_multipliers[i]}',
                  ],
                  freeSpinsSliceIndex: _multipliers
                      .indexWhere((int m) => m == _freeSpinsMarker),
                  idleController: _idleController,
                  spinController: _spinController,
                  finalRotation: _finalRotation,
                  mega: _mega,
                ),
                const Spacer(),
                if (_finished)
                  _WinPanel(
                    coins: _awardedCoins,
                    freeSpins: _awardedFreeSpins,
                  )
                else if (!_spinning)
                  _SpinCta(onTap: _spin, mega: _mega)
                else
                  const _SpinningIndicator(),
                const SizedBox(height: 24),
                if (_finished)
                  _CollectButton(
                    onTap: () => Navigator.of(context).pop(
                      BonusResult(
                        coins: _awardedCoins,
                        freeSpins: _awardedFreeSpins,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BonusHeader extends StatelessWidget {
  const _BonusHeader({required this.mega});
  final bool mega;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          mega ? 'MEGA BONUS' : 'BONUS ROUND',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            shadows: <Shadow>[
              Shadow(
                blurRadius: 20,
                color: mega
                    ? const Color(0xFFFFC107).withValues(alpha: 0.95)
                    : const Color(0xFF00BFFF).withValues(alpha: 0.95),
              ),
              const Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          mega
              ? 'Bigger prizes for 4+ scatters'
              : 'Spin the Wheel of Golden Crown',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _WheelStack extends StatelessWidget {
  const _WheelStack({
    required this.wheelSize,
    required this.slices,
    required this.labels,
    required this.freeSpinsSliceIndex,
    required this.idleController,
    required this.spinController,
    required this.finalRotation,
    required this.mega,
  });

  final double wheelSize;
  final int slices;
  final List<String> labels;
  final int freeSpinsSliceIndex;
  final AnimationController idleController;
  final AnimationController spinController;
  final double finalRotation;
  final bool mega;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wheelSize,
      height: wheelSize + 30,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Wheel with rotation.
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[spinController, idleController]),
            builder: (BuildContext context, _) {
              final double t = spinController.value;
              final double idle = idleController.value;
              // Slow idle wobble when not spinning.
              final double idleRot = spinController.value == 0
                  ? math.sin(idle * 2 * math.pi) * 0.03
                  : 0;
              final double rot = t * finalRotation + idleRot;
              return Transform.rotate(
                angle: rot,
                child: CustomPaint(
                  size: Size.square(wheelSize),
                  painter: _WheelPainter(
                    slices: slices,
                    labels: labels,
                    mega: mega,
                    freeSpinsSliceIndex: freeSpinsSliceIndex,
                  ),
                ),
              );
            },
          ),

          // Center hub.
          Container(
            width: wheelSize * 0.22,
            height: wheelSize * 0.22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: mega
                    ? const <Color>[
                        Color(0xFFFFF7A8),
                        Color(0xFFFFC107),
                        Color(0xFF8D6E00),
                      ]
                    : const <Color>[
                        Color(0xFFB0EBFF),
                        Color(0xFF00BFFF),
                        Color(0xFF003C6E),
                      ],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: (mega
                          ? const Color(0xFFFFC107)
                          : const Color(0xFF00BFFF))
                      .withValues(alpha: 0.7),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'SPIN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: <Shadow>[
                  Shadow(blurRadius: 4, color: Colors.black),
                ],
              ),
            ),
          ),

          // Pointer/arrow at the top.
          Positioned(
            top: -2,
            child: _WheelPointer(size: wheelSize * 0.12),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.slices,
    required this.labels,
    required this.mega,
    required this.freeSpinsSliceIndex,
  });
  final int slices;
  final List<String> labels;
  final bool mega;
  final int freeSpinsSliceIndex;

  static const List<Color> _sliceColors = <Color>[
    Color(0xFF002A55),
    Color(0xFF00477A),
    Color(0xFF01669F),
    Color(0xFF0087C4),
    Color(0xFF00A5E0),
    Color(0xFF01669F),
    Color(0xFF00477A),
    Color(0xFF003060),
  ];

  static const List<Color> _megaSliceColors = <Color>[
    Color(0xFF5D3A00),
    Color(0xFF8D5A00),
    Color(0xFFB8860B),
    Color(0xFFD4A017),
    Color(0xFFFFC107),
    Color(0xFFB8860B),
    Color(0xFF8D5A00),
    Color(0xFF4A2C00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = size.width / 2;
    final double sliceAngle = 2 * math.pi / slices;

    // Outer ring.
    final Paint ring = Paint()
      ..shader = SweepGradient(
        colors: mega
            ? const <Color>[
                Color(0xFFFFC107),
                Color(0xFFFFF7A8),
                Color(0xFFFFC107),
                Color(0xFFFFF7A8),
                Color(0xFFFFC107),
              ]
            : const <Color>[
                Color(0xFF00BFFF),
                Color(0xFFB0EBFF),
                Color(0xFF00BFFF),
                Color(0xFFB0EBFF),
                Color(0xFF00BFFF),
              ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, ring);

    final double innerR = r - 8;
    final Rect inner = Rect.fromCircle(center: c, radius: innerR);

    // Draw slices from -pi/2 (top) so slice 0 is centered at pointer.
    final double startBase = -math.pi / 2 - sliceAngle / 2;
    final List<Color> sliceColors = mega ? _megaSliceColors : _sliceColors;
    for (int i = 0; i < slices; i++) {
      final double start = startBase + i * sliceAngle;
      final Paint p = Paint()
        ..color = i == freeSpinsSliceIndex
            ? const Color(0xFF3E2723)
            : sliceColors[i % sliceColors.length];
      canvas.drawArc(inner, start, sliceAngle, true, p);

      // Slice separators.
      final Offset edge = c +
          Offset(math.cos(start) * innerR, math.sin(start) * innerR);
      canvas.drawLine(
        c,
        edge,
        Paint()
          ..color = (mega ? const Color(0xFFFFC107) : const Color(0xFF00BFFF))
              .withValues(alpha: 0.6)
          ..strokeWidth = 2,
      );
    }

    // Slice labels.
    for (int i = 0; i < slices; i++) {
      final double center = startBase + (i + 0.5) * sliceAngle;
      final Offset pos = c +
          Offset(
            math.cos(center) * innerR * 0.62,
            math.sin(center) * innerR * 0.62,
          );

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(center + math.pi / 2);

      final bool isFree = i == freeSpinsSliceIndex;
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: isFree ? const Color(0xFFFFE082) : Colors.white,
            fontSize: isFree ? r * 0.095 : r * 0.13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            height: 1.05,
            shadows: <Shadow>[
              Shadow(
                blurRadius: isFree ? 10 : 6,
                color: isFree
                    ? const Color(0xFFFFB300).withValues(alpha: 0.9)
                    : Colors.black.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // Rim bumps (little studs around the ring).
    const int studs = 16;
    for (int i = 0; i < studs; i++) {
      final double a = -math.pi / 2 + i * (2 * math.pi / studs);
      final Offset s = c + Offset(math.cos(a) * (r - 4), math.sin(a) * (r - 4));
      canvas.drawCircle(
        s,
        3,
        Paint()..color = mega
            ? const Color(0xFFFFF7A8)
            : const Color(0xFFB0EBFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.slices != slices ||
      old.labels != labels ||
      old.mega != mega ||
      old.freeSpinsSliceIndex != freeSpinsSliceIndex;
}

class _WheelPointer extends StatelessWidget {
  const _WheelPointer({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.4),
      painter: _PointerPainter(),
    );
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawShadow(p, Colors.black, 6, false);

    canvas.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFFFFF7A8), Color(0xFFFFC107)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SpinCta extends StatelessWidget {
  const _SpinCta({required this.onTap, required this.mega});
  final VoidCallback onTap;
  final bool mega;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: mega
                ? const <Color>[Color(0xFFFFF7A8), Color(0xFFFFB300)]
                : const <Color>[Color(0xFF00BFFF), Color(0xFF003C6E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: (mega
                      ? const Color(0xFFFFB300)
                      : const Color(0xFF00BFFF))
                  .withValues(alpha: 0.6),
              blurRadius: 22,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          mega ? 'SPIN MEGA WHEEL' : 'SPIN THE WHEEL',
          style: TextStyle(
            color: mega ? const Color(0xFF3E2723) : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}

class _SpinningIndicator extends StatelessWidget {
  const _SpinningIndicator();
  @override
  Widget build(BuildContext context) {
    return const Text(
      'GOOD LUCK...',
      style: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
    );
  }
}

class _WinPanel extends StatelessWidget {
  const _WinPanel({required this.coins, required this.freeSpins});
  final int coins;
  final int freeSpins;

  @override
  Widget build(BuildContext context) {
    final bool isFree = freeSpins > 0;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      tween: Tween<double>(begin: 0, end: 1),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double v, Widget? child) {
        return Transform.scale(scale: v, child: child);
      },
      child: Column(
        children: <Widget>[
          Text(
            isFree ? 'YOU WON' : 'YOU WON',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              shadows: <Shadow>[
                Shadow(
                  blurRadius: 12,
                  color: const Color(0xFFFFC107).withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isFree ? '$freeSpins FREE SPINS' : '$coins',
            style: TextStyle(
              color: const Color(0xFFFFE082),
              fontSize: isFree ? 30 : 46,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: <Shadow>[
                Shadow(
                  blurRadius: 22,
                  color: const Color(0xFFFFB300).withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectButton extends StatelessWidget {
  const _CollectButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFFFFF7A8), Color(0xFFFFB300)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFFFB300).withValues(alpha: 0.7),
              blurRadius: 22,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Text(
          'COLLECT',
          style: TextStyle(
            color: Color(0xFF3E2723),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}
