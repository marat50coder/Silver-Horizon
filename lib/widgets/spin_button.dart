import 'package:flutter/material.dart';

/// Animated play/spin button using the [play_button.webp] asset.
class SpinButton extends StatefulWidget {
  const SpinButton({
    super.key,
    required this.onTap,
    this.disabled = false,
  });

  final VoidCallback onTap;
  final bool disabled;

  @override
  State<SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<SpinButton>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _breath.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!widget.disabled) _press.forward();
      },
      onTapCancel: () => _press.reverse(),
      onTapUp: (_) => _press.reverse(),
      onTap: widget.disabled ? null : widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_breath, _press]),
        builder: (BuildContext context, _) {
          final double breath = widget.disabled ? 0.0 : _breath.value;
          final double press = _press.value;
          final double scale = (1 + breath * 0.04) * (1 - press * 0.09);
          final double glow = widget.disabled ? 0.15 : (0.45 + 0.35 * breath);
          return Opacity(
            opacity: widget.disabled ? 0.55 : 1,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF00BFFF).withValues(alpha: glow),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/Silver_Horizon_gameplay_assets/play_button.webp',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
