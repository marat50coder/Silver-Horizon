import 'package:flutter/material.dart';

import 'app_layout.dart';

/// Shared full-screen scaffold used by secondary screens (paytable, daily
/// bonus, missions, stats). Renders the game background darkened, a big
/// glowing title header and a circular back button.
///
/// On iPad the header + content column are clamped to [AppLayout.contentMaxWidth]
/// so the UI stays grouped rather than stretching across a huge screen.
class ThemedScaffold extends StatelessWidget {
  const ThemedScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/Silver_Horizon_gameplay_assets/background_game.webp',
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withValues(alpha: 0.55)),
          SafeArea(
            child: AppLayout.constrained(
              context: context,
              maxWidth: AppLayout.contentMaxWidth(context),
              child: Column(
                children: <Widget>[
                  _Header(title: title, trailing: trailing),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: <Widget>[
          CircleBackButton(onTap: () => Navigator.of(context).pop()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                shadows: <Shadow>[
                  Shadow(
                    blurRadius: 14,
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 44, child: trailing),
        ],
      ),
    );
  }
}

class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xAA001A33),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF00BFFF).withValues(alpha: 0.75),
              width: 1.4,
            ),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

BoxDecoration tileDecoration({Color? tint}) => BoxDecoration(
      color: const Color(0xAA001A33),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: (tint ?? const Color(0xFF00BFFF)).withValues(alpha: 0.5),
        width: 1.2,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: (tint ?? const Color(0xFF00BFFF)).withValues(alpha: 0.15),
          blurRadius: 12,
        ),
      ],
    );
