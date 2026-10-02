import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tideway/core/gleam_models.dart';
import '../tideway/gleam_coordinator.dart';
import '../tideway/infra/signal_reach.dart';
import '../tideway/infra/tide_boot.dart';
import '../tideway/pages/gleam_invitation.dart';
import '../tideway/pages/horizon_portal.dart';
import '../tideway/pages/quiet_tide_page.dart';
import 'main_menu_screen.dart';

/// Loading screen that supports both portrait and landscape orientations.
/// Plays the branded splash while [GleamCoordinator.decide] resolves the
/// first destination, then routes to the native menu, portal, or offline page.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    this.coordinator,
    this.fromOfflineRetry = false,
    this.reachConfirmed = false,
  });

  final GleamCoordinator? coordinator;

  /// True when this splash was opened from the no-wifi Retry / reconnect.
  /// The offline page already proved a route out, so this screen is the
  /// loading step and must not hand back to nowifi.
  final bool fromOfflineRetry;

  /// True when boot already proved reachability before this widget existed.
  /// The splash may paint immediately; a second probe must not cover it
  /// with the offline page.
  final bool reachConfirmed;

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
  // Splash artwork stays hidden until we know this launch is allowed to
  // show loading. A cold start with no route out never sets this: that
  // path is the offline page, built before this widget.
  bool _preflightDone = false;
  bool _bootSettled = false;
  StreamSubscription<List<ConnectivityResult>>? _radio;

  @override
  void initState() {
    super.initState();
    _bootSettled = widget.fromOfflineRetry || widget.reachConfirmed;
    _preflightDone = _bootSettled;

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    if (_preflightDone) {
      _progressController.forward();
    }

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

    _hardDeadline = Timer(const Duration(seconds: 36), () async {
      if (!mounted || _navigated) return;
      // The reachability gate never finished. Do not invent a native
      // destination — that drops a no-radio first launch into the game
      // and the offline page never appears.
      if (!_bootSettled) {
        await _openNowifiNow();
        return;
      }
      _barDone = true;
      if (_destination == null) {
        // Returning gray-funnel users must NEVER fall through to the
        // white game when `decide()` times out — AppsFlyer's handshake
        // can stall on slow radios, but the server already classified
        // this install as portal on a previous launch. Prefer the
        // cached URL, then the saved route, then the native fallback.
        final coordinator = widget.coordinator;
        if (coordinator != null && coordinator.vault.grayAttributed) {
          final cached = await coordinator.vault.savedUrl();
          if (cached != null && cached.isNotEmpty) {
            _destination = PortalTide(cached);
          }
        }
        _destination ??= const NativeTide();
      }
      _maybeNavigate();
    });

    unawaited(_startPipeline());
    _watchRadioDrop();
  }

  /// Watches for the radio dropping while the splash is on screen.
  ///
  /// Without this, dropping Wi-Fi / cellular mid-way through `decide()`
  /// (OneLink install → open → disable radio before the config POST
  /// finishes) leaves AppsFlyer and the config `HTTP POST` hanging on
  /// dead sockets. The 36 s hard deadline then runs out before the user
  /// sees anything. The listener bails to the nowifi page the moment
  /// `connectivity_plus` reports no interface, so Retry picks up a
  /// clean pipeline.
  void _watchRadioDrop() {
    final coordinator = widget.coordinator;
    if (coordinator == null) return;
    _radio = coordinator.probe.changes.listen((states) {
      if (_navigated || !mounted) return;
      if (SignalReach.radiosUp(states)) return;
      assert(() {
        debugPrint('[HZ.LOAD] radio dropped mid-splash → nowifi');
        return true;
      }());
      unawaited(_openNowifiNow());
    });
  }

  /// Same shape as NeonPlumeDrop `IgniteScreen._begin`, except the
  /// offline redirect is skipped once boot or Retry already proved a
  /// route out. Showing the splash and then the offline page is the
  /// order a first launch must not take.
  ///
  ///   1. vault/prefs initialise (cheap, needed for route lookup);
  ///   2. quickReach — only when this screen was opened with no prior
  ///      proof. No radio → nowifi, and the splash was never painted;
  ///   3. Firebase / AppCheck warm up (TideBoot);
  ///   4. hasInterface re-check, same condition as step 2;
  ///   5. the splash is revealed and `decide()` runs attribution.
  Future<void> _startPipeline() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final coordinator = widget.coordinator;
    final holdSplash = !widget.fromOfflineRetry && !widget.reachConfirmed;
    try {
      await coordinator?.vault.initialize();
    } catch (_) {}
    if (!mounted) return;
    if (holdSplash &&
        coordinator != null &&
        !await coordinator.probe.quickReach()) {
      assert(() {
        debugPrint('[HZ.LOAD] offline at boot → nowifi fast-path');
        return true;
      }());
      await _openNowifiNow();
      return;
    }
    try {
      await coordinator?.agent.prepare();
    } catch (_) {}
    try {
      await TideBoot.ensureProduction();
    } catch (_) {}
    if (!mounted) return;
    if (holdSplash &&
        coordinator != null &&
        !await coordinator.probe.hasInterface()) {
      await _openNowifiNow();
      return;
    }
    _bootSettled = true;
    if (!_preflightDone) {
      setState(() => _preflightDone = true);
      _progressController.forward();
    }
    unawaited(_resolveDestination());
  }

  Future<void> _openNowifiNow() async {
    _destination = const OfflineTide(returnToNative: false);
    _barDone = true;
    await _maybeNavigate();
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
    if (_destination is! OfflineTide) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
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
            retryBuilder: (_) => LoadingScreen(
              coordinator: coordinator,
              fromOfflineRetry: true,
            ),
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
    unawaited(_radio?.cancel());
    _progressController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  bool get _revealSplash =>
      widget.fromOfflineRetry || widget.reachConfirmed || _preflightDone;

  @override
  Widget build(BuildContext context) {
    if (!_revealSplash) {
      return const Scaffold(backgroundColor: Colors.black);
    }
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
              if (_preflightDone)
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
