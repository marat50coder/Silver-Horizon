import 'package:flutter/material.dart';

/// Row of bet-tile buttons rendered with the "on" / "off" bet assets.
class BetSelector extends StatelessWidget {
  const BetSelector({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<int> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double gap = 8;
        final double tileSize =
            (constraints.maxWidth - gap * (options.length - 1)) /
                options.length;
        return SizedBox(
          height: tileSize,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < options.length; i++) ...<Widget>[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: _BetTile(
                    value: options[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BetTile extends StatefulWidget {
  const _BetTile({
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_BetTile> createState() => _BetTileState();
}

class _BetTileState extends State<_BetTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: widget.selected ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant _BetTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.selected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final double t = Curves.easeOutBack.transform(_controller.value.clamp(0, 1));
          final double scale = 1 + 0.08 * t;
          return Transform.scale(
            scale: scale,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // "Off" (silver) frame — always visible.
                  Image.asset(
                    'assets/Silver_Horizon_gameplay_assets/bet_number_of_bets_asset_of.webp',
                    fit: BoxFit.contain,
                  ),
                  // "On" (blue) frame — fades in when selected.
                  Opacity(
                    opacity: _controller.value,
                    child: Image.asset(
                      'assets/Silver_Horizon_gameplay_assets/bet_number_of_bets_asset_on.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                  // Bet number label.
                  Center(
                    child: Text(
                      '${widget.value}',
                      style: TextStyle(
                        color: widget.selected
                            ? Colors.white
                            : const Color(0xFFCFD8DC),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        shadows: <Shadow>[
                          Shadow(
                            blurRadius: widget.selected ? 10 : 4,
                            color: widget.selected
                                ? const Color(0xFF00BFFF)
                                : Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
