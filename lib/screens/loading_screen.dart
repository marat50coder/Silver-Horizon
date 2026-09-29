import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main_menu_screen.dart';

/// Loading screen that supports both portrait and landscape orientations.
/// A horizontal progress bar fills from left to right and reaches 100% only
/// at the very moment right before the game screen is launched.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final AnimationController _dotsController;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // Progress animation: total loading duration is 4.5s. We ease the curve so
    // the bar takes its time in the middle and completes only right before
    // navigation, giving a satisfying "final push" feel.
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );

    // Dots animation cycles Loading. -> Loading.. -> Loading... every 500ms.
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _progressController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed && !_navigated) {
        _navigated = true;
        // Small delay so the user can see the fully-filled bar for a beat.
        Future<void>.delayed(const Duration(milliseconds: 250), _goToGame);
      }
    });

    // Kick things off after the first frame so the screen is painted first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _progressController.forward();
    });
  }

  Future<void> _goToGame() async {
    // Lock to portrait BEFORE we build the menu/game so it starts vertical.
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (_, _, _) => const MainMenuScreen(),
        transitionsBuilder: (_, Animation<double> anim, _, Widget child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (BuildContext context, Orientation orientation) {
          final bool isPortrait = orientation == Orientation.portrait;
          final String bg = isPortrait
              ? 'assets/Silver_Horizon_additional_assets/Vertical_Loading_Screen.webp'
              : 'assets/Silver_Horizon_additional_assets/Horizontal_Loading_Screen.webp';

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Background loading art fills the whole surface, cropping if
              // necessary so there are no empty borders.
              Image.asset(bg, fit: BoxFit.cover),

              // Subtle vignette to make the progress bar pop.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, 0.6),
                    radius: 1.2,
                    colors: <Color>[
                      Colors.transparent,
                      Color(0x66000000),
                    ],
                  ),
                ),
                child: SizedBox.expand(),
              ),

              // Progress bar + Loading text pinned near the bottom.
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isPortrait ? 40 : 96,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _LoadingText(controller: _dotsController),
                      const SizedBox(height: 14),
                      _ProgressBar(controller: _progressController),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingText extends StatelessWidget {
  const _LoadingText({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final int dotCount = ((controller.value * 3).floor() % 3) + 1;
        final String dots = '.' * dotCount;
        return Text(
          'Loading$dots',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            shadows: <Shadow>[
              Shadow(
                blurRadius: 18,
                color: const Color(0xFF00BFFF).withValues(alpha: 0.85),
              ),
              const Shadow(blurRadius: 4, color: Colors.black),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        // Custom curve: eases slowly in the middle, snaps to 1.0 at the end so
        // the bar visually completes only right before navigation.
        final double raw = controller.value;
        final double eased = _loadingCurve(raw);
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth;
            return Container(
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xAA000814),
                border: Border.all(
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.9),
                  width: 1.5,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: <Widget>[
                    // Fill.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: width * eased,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Color(0xFF003C6E),
                              Color(0xFF00BFFF),
                              Color(0xFFB0EBFF),
                            ],
                            stops: <double>[0.0, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Moving shine highlight riding along the fill.
                    if (eased > 0.02 && eased < 0.99)
                      Positioned(
                        left: (width * eased) - 30,
                        top: 0,
                        bottom: 0,
                        width: 40,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: 0.7),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _loadingCurve(double t) {
    // Keep the fill under 90% until the last ~7% of time, then jump to 100%.
    if (t >= 0.93) {
      final double k = (t - 0.93) / 0.07;
      return 0.9 + 0.1 * Curves.easeOut.transform(k.clamp(0.0, 1.0));
    }
    final double base = t / 0.93; // 0..1 within the pre-final segment
    return 0.9 * Curves.easeInOutCubic.transform(base);
  }
}
