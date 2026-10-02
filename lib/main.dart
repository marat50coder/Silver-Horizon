import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';
import 'tideway/config/gleam_horizon_config.dart';
import 'tideway/core/gleam_models.dart';
import 'tideway/gleam_coordinator.dart';
import 'tideway/infra/gleam_attribution.dart';
import 'tideway/infra/gleam_exchange.dart';
import 'tideway/infra/horizon_agent.dart';
import 'tideway/infra/horizon_beacon.dart';
import 'tideway/infra/horizon_vault.dart';
import 'tideway/infra/signal_reach.dart';
import 'tideway/pages/quiet_tide_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(() {
    debugPrint(
      '[HZ.BOOT] credentialsReady=${GleamHorizonConfig.grayCredentialsReady} '
      'endpoint=${GleamHorizonConfig.endpoint} '
      'afKeyLen=${GleamHorizonConfig.appsFlyerKey.length} '
      'fbNum=${GleamHorizonConfig.firebaseProjectNumber}',
    );
    return true;
  }());

  final vault = HorizonVault();
  final agent = HorizonAgent();
  final probe = SignalReach();
  // HorizonBeacon stays lazy: Firebase is not touched until a launch
  // that already has a route out. A first launch with no route must
  // paint the offline page before any splash.
  final notifications = HorizonBeacon(
    vault,
    enabled: GleamHorizonConfig.grayCredentialsReady,
  );
  final attribution = GleamAttribution(agent, vault: vault);
  final coordinator = GleamCoordinator(
    vault: vault,
    probe: probe,
    attribution: attribution,
    exchange: GleamExchange(agent, vault),
    notifications: notifications,
    agent: agent,
    runtimeEnabled: GleamHorizonConfig.grayCredentialsReady,
  );

  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Only the on-disk route is read before the first frame. SharedPreferences
  // comes back in <100 ms on a warm boot; a hard 350 ms cap means a slow
  // cold boot cannot delay the paint. Reachability is NOT probed here —
  // iOS keeps the launch screen on until runApp fires, so any await above
  // this line is a visible black / navy pause before nowifi can show.
  var startRoute = TideRoute.undecided;
  try {
    await vault.initialize().timeout(const Duration(milliseconds: 350));
    startRoute = vault.route;
  } catch (_) {}
  assert(() {
    debugPrint('[HZ.BOOT] startRoute=$startRoute');
    return true;
  }());

  runApp(
    SilverHorizonApp(coordinator: coordinator, startRoute: startRoute),
  );
}

class SilverHorizonApp extends StatelessWidget {
  const SilverHorizonApp({
    super.key,
    this.coordinator,
    this.startRoute = TideRoute.undecided,
  });

  final GleamCoordinator? coordinator;

  /// Route stored on disk when the app process started. Decides whether
  /// the first widget should be the splash (settled native install) or
  /// the no-wifi gate (fresh install / returning portal — both can be
  /// offline on a cold start and must never flash the splash first).
  final TideRoute startRoute;

  @override
  Widget build(BuildContext context) {
    precacheImage(
      const AssetImage(
        'assets/Silver_Horizon_additional_assets/sh_splash_portrait.webp',
      ),
      context,
    );
    precacheImage(
      const AssetImage(
        'assets/Silver_Horizon_additional_assets/sh_splash_landscape.webp',
      ),
      context,
    );

    return MaterialApp(
      title: 'Silver Horizon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A6FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Roboto',
      ),
      home: _home(),
    );
  }

  Widget _home() {
    final coordinator = this.coordinator;
    if (coordinator == null || startRoute == TideRoute.native) {
      // Settled native install goes straight to the splash — the game
      // works offline, so a nowifi gate would strand the user.
      return LoadingScreen(
        coordinator: coordinator,
        reachConfirmed: coordinator != null,
      );
    }
    // Fresh install / returning portal: render nowifi as the very first
    // Flutter frame so an offline user sees it instantly. The storyboard
    // navy underneath matches the top of the nowifi gradient, so the
    // transition from the native launch screen is invisible. Online
    // users are swapped to the loading splash by the silent probe
    // inside QuietTidePage.
    return QuietTidePage(
      probe: coordinator.probe,
      probeOnMount: true,
      retryBuilder: (_) => LoadingScreen(
        coordinator: coordinator,
        fromOfflineRetry: true,
      ),
    );
  }
}

