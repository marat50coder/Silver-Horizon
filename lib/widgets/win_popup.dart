import 'package:flutter/material.dart';

/// Animated overlay that celebrates a win with a big number and a subtitle.
///
/// Fades in with an elastic pop and holds for [visibleDuration], then fades
/// away. Rendered above the reels but doesn't intercept touches.
class WinPopup extends StatefulWidget {
  const WinPopup({
    super.key,
    required this.amount,
    required this.lineCount,
    required this.onDone,
    this.visibleDuration = const Duration(milliseconds: 3200),
  });

  final int amount;
  final int lineCount;
  final VoidCallback onDone;
  final Duration visibleDuration;

  @override
  State<WinPopup> createState() => _WinPopupState();
}

class _WinPopupState extends State<WinPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    Future<void>.delayed(widget.visibleDuration + const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      await _c.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Compact banner floating just above the reel area, so the payline
    // overlay stays fully visible while the amount is shown.
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -1.05),
        child: AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, Widget? child) {
            final double t = Curves.easeOutBack.transform(_c.value.clamp(0, 1));
            return Opacity(
              opacity: _c.value,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * -10),
                child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  Color(0xF2001A33),
                  Color(0xF2002A55),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFFFFD54F).withValues(alpha: 0.95),
                width: 1.5,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.6),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.lineCount == 1
                      ? 'WIN'
                      : '${widget.lineCount} LINES  •  WIN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    shadows: <Shadow>[
                      Shadow(
                        blurRadius: 10,
                        color: const Color(0xFF00BFFF).withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _AnimatedNumber(target: widget.amount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedNumber extends StatelessWidget {
  const _AnimatedNumber({required this.target});
  final int target;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, _) {
        return Text(
          '+${v.round()}',
          style: TextStyle(
            color: const Color(0xFFFFE082),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            shadows: <Shadow>[
              Shadow(
                blurRadius: 16,
                color: const Color(0xFFFFB300).withValues(alpha: 0.95),
              ),
              const Shadow(blurRadius: 3, color: Colors.black),
            ],
          ),
        );
      },
    );
  }
}
