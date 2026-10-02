import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tideway/core/gleam_models.dart';
import '../tideway/gleam_coordinator.dart';
import '../tideway/pages/gleam_invitation.dart';
import '../tideway/pages/horizon_portal.dart';
import '../tideway/pages/quiet_tide_page.dart';
import 'main_menu_screen.dart';

/// Loading screen that supports both portrait and landscape orientations.
/// Plays the branded splash while [GleamCoordinator.decide] resolves the
/// first destination, then routes to the native menu, portal, or offline page.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, this.coordinator});

  final GleamCoordinator? coordinator;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final AnimationController _dotsController;
  bool _navigated = false;
  bool _barDone = false;
  TideDestination? _destination;
  Timer? _hardDeadline;
  // On a cold start without any network interface we never want to flash the
  // splash + progress bar: the user asked for the no-wifi screen to come up
  // first and the pipeline to defer AppsFlyer / config work until a Retry.
  bool _preflightDone = false;
  bool _preflightOffline = false;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _progressController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _barDone = true;
        _maybeNavigate();
      }
    });

    // Lesson #25 floor: a dead-end offline verdict that takes the full splash
    // to admit it feels broken. If the destination resolves to offline before
    // the bar finishes, release the splash after ~0.75s instead of 4.5s.
    Timer(const Duration(milliseconds: 750), () {
      if (!mounted || _navigated) return;
      if (_destination is OfflineTide) {
        _barDone = true;
        _maybeNavigate();
      }
    });

    _hardDeadline = Timer(const Duration(seconds: 36), () {
      _barDone = true;
      _destination ??= const NativeTide();
      _maybeNavigate();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final coordinator = widget.coordinator;
      if (coordinator != null) {
        final online = await coordinator.probe.hasInterface();
        if (!mounted) return;
        if (!online) {
          _preflightDone = true;
          _preflightOffline = true;
          _navigated = true;
          _hardDeadline?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => QuietTidePage(
                probe: coordinator.probe,
                retryBuilder: (_) =>
                    LoadingScreen(coordinator: coordinator),
              ),
            ),
          );
          return;
        }
      }
      _preflightDone = true;
      if (mounted) setState(() {});
      _progressController.forward();
      unawaited(_resolveDestination());
    });
  }

  Future<void> _resolveDestination() async {
    final coordinator = widget.coordinator;
    if (coordinator == null) {
      _destination = const NativeTide();
      _maybeNavigate();
      return;
    }
    try {
      _destination = await coordinator.decide(
        onProgress: (value) {
          if (!mounted) return;
          if (value > _progressController.value) {
            _progressController.value = value.clamp(0.0, 1.0);
          }
        },
      );
    } catch (_) {
      _destination = const NativeTide();
    }
    _maybeNavigate();
  }

  Future<void> _maybeNavigate() async {
    if (_navigated || !_barDone || _destination == null) return;
    _navigated = true;
    _hardDeadline?.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _openDestination(_destination!);
  }

  Future<void> _openDestination(TideDestination destination) async {
    final coordinator = widget.coordinator;

    if (destination is NativeTide || coordinator == null) {
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
      return;
    }

    if (destination is OfflineTide) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => QuietTidePage(
            probe: coordinator.probe,
            retryBuilder: (_) => LoadingScreen(coordinator: coordinator),
          ),
        ),
      );
      return;
    }

    if (destination is PortalTide) {
      Widget portalBuilder(BuildContext _) => HorizonPortal(
        url: destination.url,
        coldLaunch: destination.coldLaunch,
        vault: coordinator.vault,
        probe: coordinator.probe,
        notifications: coordinator.notifications,
        agent: coordinator.agent,
      );

      if (coordinator.vault.shouldShowPushInvite &&
          await coordinator.notifications.canOfferPermission()) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => GleamInvitation(
              vault: coordinator.vault,
              notifications: coordinator.notifications,
              nextBuilder: portalBuilder,
            ),
          ),
        );
      } else if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: portalBuilder),
        );
      }
    }
  }

  @override
  void dispose() {
    _hardDeadline?.cancel();
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
              ? 'assets/Silver_Horizon_additional_assets/sh_splash_portrait.webp'
              : 'assets/Silver_Horizon_additional_assets/sh_splash_landscape.webp';

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
              // Hidden until the connectivity preflight passes so an offline
              // cold start never flashes the splash before the no-wifi page.
              if (_preflightDone && !_preflightOffline)
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
