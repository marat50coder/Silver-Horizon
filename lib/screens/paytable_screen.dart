import 'package:flutter/material.dart';

import '../models/payline.dart';
import '../models/slot_symbol.dart';
import '../widgets/themed_scaffold.dart';

/// Paytable / info screen: shows every symbol with its 3/4/5-of-a-kind
/// multiplier, the shape of every payline, and the special rules for the
/// Wild, Bar and Scatter tiles.
class PaytableScreen extends StatelessWidget {
  const PaytableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'PAYTABLE',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const _SectionTitle('SYMBOLS & PAYOUTS'),
          const SizedBox(height: 8),
          const _PayoutHeader(),
          const SizedBox(height: 4),
          for (final SlotSymbol s in _paying) _SymbolPayoutRow(symbol: s),
          const SizedBox(height: 20),
          const _SectionTitle('SPECIAL TILES'),
          const SizedBox(height: 8),
          const _SpecialTileRow(
            symbol: SlotSymbol.bar,
            title: 'BAR — Wild Substitute',
            description:
                'Substitutes for any regular symbol to complete a line. '
                'Bar tiles themselves do not pay.',
          ),
          const _SpecialTileRow(
            symbol: SlotSymbol.wild,
            title: 'WILD — Line Extender',
            description:
                'Replaces any symbol on a payline. Great for chaining longer '
                'wins with your best paying symbols.',
          ),
          const _SpecialTileRow(
            symbol: SlotSymbol.scatter,
            title: 'SCATTER — Bonus Trigger',
            description:
                '3+ scatters anywhere on the grid open the BONUS WHEEL. '
                '4 scatters unlock the MEGA WHEEL with much bigger prizes.',
          ),
          const SizedBox(height: 20),
          const _SectionTitle('10 PAYLINES'),
          const SizedBox(height: 8),
          _PaylinesGrid(),
          const SizedBox(height: 20),
          const _SectionTitle('BONUS ROUND'),
          const SizedBox(height: 8),
          const _BonusExplainer(),
          const SizedBox(height: 24),
          _FooterNote(),
        ],
      ),
    );
  }

  static final List<SlotSymbol> _paying = <SlotSymbol>[
    SlotSymbol.cherry,
    SlotSymbol.grape,
    SlotSymbol.watermelon,
    SlotSymbol.clever,
    SlotSymbol.bell,
    SlotSymbol.star,
    SlotSymbol.diamond,
    SlotSymbol.crown,
  ];
}

class _SymbolPayoutRow extends StatelessWidget {
  const _SymbolPayoutRow({required this.symbol});
  final SlotSymbol symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: tileDecoration(),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 46,
            height: 46,
            child: Image.asset(symbol.assetPath, fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _prettyName(symbol),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                fontSize: 14,
              ),
            ),
          ),
          _PayColumn(label: '3×', value: symbol.payout(3)),
          const SizedBox(width: 10),
          _PayColumn(label: '4×', value: symbol.payout(4)),
          const SizedBox(width: 10),
          _PayColumn(label: '5×', value: symbol.payout(5)),
        ],
      ),
    );
  }

  String _prettyName(SlotSymbol s) {
    switch (s) {
      case SlotSymbol.cherry:
        return 'CHERRY';
      case SlotSymbol.grape:
        return 'GRAPE';
      case SlotSymbol.watermelon:
        return 'WATERMELON';
      case SlotSymbol.clever:
        return 'CLOVER';
      case SlotSymbol.bell:
        return 'BELL';
      case SlotSymbol.star:
        return 'STAR';
      case SlotSymbol.diamond:
        return 'DIAMOND';
      case SlotSymbol.crown:
        return 'CROWN';
      case SlotSymbol.bar:
        return 'BAR';
      case SlotSymbol.wild:
        return 'WILD';
      case SlotSymbol.scatter:
        return 'SCATTER';
    }
  }
}

class _PayColumn extends StatelessWidget {
  const _PayColumn({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          Text(
            'x$value',
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutHeader extends StatelessWidget {
  const _PayoutHeader();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        'Multipliers are applied to your current bet. 3, 4 or 5 matching '
        'symbols from the left across an active payline pay out.',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SpecialTileRow extends StatelessWidget {
  const _SpecialTileRow({
    required this.symbol,
    required this.title,
    required this.description,
  });
  final SlotSymbol symbol;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: tileDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 52,
            height: 52,
            child: Image.asset(symbol.assetPath, fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFFFE082),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
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

class _PaylinesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const int columns = 2;
        const double gap = 10;
        final double tileWidth = (c.maxWidth - gap * (columns - 1)) / columns;
        final double tileHeight = tileWidth * 0.55;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (int i = 0; i < kPaylines.length; i++)
              SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: _PaylineTile(index: i),
              ),
          ],
        );
      },
    );
  }
}

class _PaylineTile extends StatelessWidget {
  const _PaylineTile({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final Payline line = kPaylines[index];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            line.name.toUpperCase(),
            style: TextStyle(
              color: line.color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(
              painter: _PaylineMiniPainter(line: line),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaylineMiniPainter extends CustomPainter {
  _PaylineMiniPainter({required this.line});
  final Payline line;

  @override
  void paint(Canvas canvas, Size size) {
    const int cols = 5;
    const int rows = 3;
    final double cellW = size.width / cols;
    final double cellH = size.height / rows;

    final Paint cellStroke = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (int c = 0; c < cols; c++) {
      for (int r = 0; r < rows; r++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH),
          cellStroke,
        );
      }
    }

    // Highlight active cells.
    final Paint cellFill = Paint()..color = line.color.withValues(alpha: 0.28);
    for (int c = 0; c < cols; c++) {
      final int r = line.rows[c];
      canvas.drawRect(
        Rect.fromLTWH(c * cellW + 1, r * cellH + 1, cellW - 2, cellH - 2),
        cellFill,
      );
    }

    // Trace line.
    final Path path = Path();
    for (int c = 0; c < cols; c++) {
      final double x = c * cellW + cellW / 2;
      final double y = line.rows[c] * cellH + cellH / 2;
      if (c == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots at each cell centre.
    for (int c = 0; c < cols; c++) {
      final Offset o = Offset(
        c * cellW + cellW / 2,
        line.rows[c] * cellH + cellH / 2,
      );
      canvas.drawCircle(o, 2.4, Paint()..color = Colors.white);
      canvas.drawCircle(o, 1.6, Paint()..color = line.color);
    }
  }

  @override
  bool shouldRepaint(covariant _PaylineMiniPainter old) => old.line != line;
}

class _BonusExplainer extends StatelessWidget {
  const _BonusExplainer();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: tileDecoration(),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'WHEEL OF SILVER HORIZON',
            style: TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '3 scatters trigger the standard wheel (up to x50 of your bet).\n'
            '4 scatters unlock the Mega Wheel (up to x100).\n'
            '5 scatters open the Grand Wheel (up to x250).',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
          shadows: <Shadow>[
            Shadow(
              blurRadius: 10,
              color: const Color(0xFF00BFFF).withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'FUN COINS • NOT REAL MONEY',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 3,
      ),
    );
  }
}

