import 'package:flutter/material.dart';

/// Responsive helpers.
///
/// The phone layout is preserved bit-for-bit (all helpers return
/// [double.infinity] on phones), while tablets clamp the content width so
/// the UI stays visually grouped in the centre instead of stretching
/// across 10"+ of screen real estate.
class AppLayout {
  AppLayout._();

  /// A device is treated as a "tablet" when its short side is >= 600 dp.
  /// This catches every current large-form-factor Android tablet.
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  /// Max width for the main menu column on iPad.
  static double menuMaxWidth(BuildContext context) =>
      isTablet(context) ? 520 : double.infinity;

  /// Max width for the primary game column (slot + status + bet + spin).
  static double gameMaxWidth(BuildContext context) =>
      isTablet(context) ? 640 : double.infinity;

  /// Max width for secondary screens (paytable, missions, stats, daily,
  /// bonus wheel, webview placeholders).
  static double contentMaxWidth(BuildContext context) =>
      isTablet(context) ? 720 : double.infinity;

  /// Wraps [child] in a centred [ConstrainedBox]. Convenience for the common
  /// "hold the content to a nice max width" pattern.
  static Widget constrained({
    required BuildContext context,
    required double maxWidth,
    required Widget child,
  }) {
    if (maxWidth.isInfinite) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
