import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';
import 'tideway/config/gleam_horizon_config.dart';
import 'tideway/gleam_coordinator.dart';
import 'tideway/infra/gleam_attribution.dart';
import 'tideway/infra/gleam_exchange.dart';
import 'tideway/infra/horizon_agent.dart';
import 'tideway/infra/horizon_beacon.dart';
import 'tideway/infra/horizon_vault.dart';
import 'tideway/infra/signal_reach.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final vault = HorizonVault();
  final agent = HorizonAgent();
  await Future.wait<void>(<Future<void>>[
    vault.initialize(),
    agent.prepare(),
  ]);

  assert(() {
    debugPrint(
      '[HZ.BOOT] credentialsReady=${GleamHorizonConfig.grayCredentialsReady} '
      'endpoint=${GleamHorizonConfig.endpoint} '
      'afKeyLen=${GleamHorizonConfig.appsFlyerKey.length} '
      'fbNum=${GleamHorizonConfig.firebaseProjectNumber}',
    );
    return true;
  }());

  var productionServicesReady = false;
  if (GleamHorizonConfig.grayCredentialsReady) {
    try {
      await Firebase.initializeApp();
      productionServicesReady = true;
      assert(() {
        debugPrint('[HZ.BOOT] Firebase.initializeApp OK');
        return true;
      }());
    } catch (error) {
      assert(() {
        debugPrint('[HZ.BOOT] Firebase.initializeApp failed: $error');
        return true;
      }());
    }
    if (productionServicesReady) {
      try {
        await FirebaseAppCheck.instance.activate(
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      } catch (error) {
        assert(() {
          debugPrint('[HZ.BOOT] AppCheck skipped: $error');
          return true;
        }());
      }
    }
  } else {
    assert(() {
      debugPrint(
        '[HZ.BOOT] gray gate DISABLED — missing credentials '
        '(endpoint/af/firebase). White part only.',
      );
      return true;
    }());
  }

  final probe = SignalReach();
  final notifications = HorizonBeacon(
    vault,
    enabled: productionServicesReady,
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

  runApp(SilverHorizonApp(coordinator: coordinator));
}

class SilverHorizonApp extends StatelessWidget {
  const SilverHorizonApp({super.key, this.coordinator});

  final GleamCoordinator? coordinator;

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
      home: LoadingScreen(coordinator: coordinator),
    );
  }
}
