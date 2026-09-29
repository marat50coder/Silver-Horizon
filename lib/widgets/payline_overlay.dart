import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/payline.dart';

/// Draws a glowing polyline through the winning payline positions.
///
/// The line is drawn only across the matched columns (matchCount), so shorter
/// wins don't draw across empty parts of the reel.
class PaylineOverlay extends StatefulWidget {
  const PaylineOverlay({
    super.key,
    required this.payline,
    required this.matchCount,
    required this.cellWidth,
    required this.cellHeight,
  });

  final Payline payline;
  final int matchCount;
  final double cellWidth;
  final double cellHeight;

  @override
  State<PaylineOverlay> createState() => _PaylineOverlayState();
}

class _PaylineOverlayState extends State<PaylineOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (BuildContext context, _) {
        return CustomPaint(
          painter: _PaylinePainter(
            payline: widget.payline,
            matchCount: widget.matchCount,
            cellWidth: widget.cellWidth,
            cellHeight: widget.cellHeight,
            pulse: _pulse.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _PaylinePainter extends CustomPainter {
  _PaylinePainter({
    required this.payline,
    required this.matchCount,
    required this.cellWidth,
    required this.cellHeight,
    required this.pulse,
  });

  final Payline payline;
  final int matchCount;
  final double cellWidth;
  final double cellHeight;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (matchCount < 2) return;

    final List<Offset> points = <Offset>[
      for (int c = 0; c < matchCount; c++)
        Offset(
          cellWidth * (c + 0.5),
          cellHeight * (payline.rows[c] + 0.5),
        ),
    ];

    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // Outer glow — pulses with animation for a lively feel.
    final Paint glow = Paint()
      ..color = payline.color.withValues(alpha: 0.35 + 0.4 * pulse)
      ..strokeWidth = 18 + 6 * pulse
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glow);

    // Main line.
    final Paint line = Paint()
      ..color = payline.color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);

    // Bright inner core.
    final Paint core = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, core);

    // Endpoint markers.
    for (final Offset p in points) {
      canvas.drawCircle(
        p,
        7 + 2 * pulse,
        Paint()
          ..color = payline.color.withValues(alpha: 0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        p,
        3,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaylinePainter old) {
    return old.pulse != pulse ||
        old.matchCount != matchCount ||
        old.payline != payline;
  }
}

/// Draws animated golden beams that connect all scatter positions on the
/// grid right before the bonus round opens. Every scatter is linked to
/// every other so the "constellation" of scatters lights up dramatically.
class ScatterConnectOverlay extends StatefulWidget {
  const ScatterConnectOverlay({
    super.key,
    required this.positions,
    required this.cellWidth,
    required this.cellHeight,
  });

  final List<(int, int)> positions;
  final double cellWidth;
  final double cellHeight;

  @override
  State<ScatterConnectOverlay> createState() => _ScatterConnectOverlayState();
}

class _ScatterConnectOverlayState extends State<ScatterConnectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
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
        return CustomPaint(
          size: Size.infinite,
          painter: _ScatterConnectPainter(
            positions: widget.positions,
            cellWidth: widget.cellWidth,
            cellHeight: widget.cellHeight,
            progress: _c.value,
          ),
        );
      },
    );
  }
}

class _ScatterConnectPainter extends CustomPainter {
  _ScatterConnectPainter({
    required this.positions,
    required this.cellWidth,
    required this.cellHeight,
    required this.progress,
  });

  final List<(int, int)> positions;
  final double cellWidth;
  final double cellHeight;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;
    final List<Offset> centers = <Offset>[
      for (final (int c, int r) in positions)
        Offset(cellWidth * (c + 0.5), cellHeight * (r + 0.5)),
    ];

    // Beam draw progress: 0 -> beams fade in and extend, 0.5 -> full
    // connections shining, 1.0 -> gentle bloom fade.
    final double beamAlpha = (progress < 0.6)
        ? (progress / 0.6).clamp(0.0, 1.0)
        : (1.0 - (progress - 0.6) / 0.4).clamp(0.0, 1.0);
    final double glowRadius = 22 + 18 * math.sin(progress * math.pi);

    // Golden beams between every pair.
    for (int i = 0; i < centers.length; i++) {
      for (int j = i + 1; j < centers.length; j++) {
        final Offset a = centers[i];
        final Offset b = centers[j];
        final Offset end = Offset.lerp(a, b, progress.clamp(0.0, 1.0))!;

        // Outer soft glow.
        canvas.drawLine(
          a,
          end,
          Paint()
            ..color =
                const Color(0xFFFFC107).withValues(alpha: 0.55 * beamAlpha)
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 14
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        // Main beam.
        canvas.drawLine(
          a,
          end,
          Paint()
            ..color =
                const Color(0xFFFFE082).withValues(alpha: 0.95 * beamAlpha)
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 4,
        );
        // Bright core.
        canvas.drawLine(
          a,
          end,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9 * beamAlpha)
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1.5,
        );
      }
    }

    // Halo at each scatter center that pulses during the connection.
    for (final Offset p in centers) {
      canvas.drawCircle(
        p,
        glowRadius,
        Paint()
          ..color = const Color(0xFFFFC107).withValues(alpha: 0.6 * beamAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawCircle(
        p,
        8,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.95 * beamAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterConnectPainter old) =>
      old.progress != progress || old.positions != positions;
}
