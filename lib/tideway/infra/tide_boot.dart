import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/gleam_horizon_config.dart';
import 'horizon_beacon.dart';

/// Shared gray-path boot so an offline first frame can skip Firebase, and
/// a later Retry can finish the same setup before loading starts. Same
/// shape as NeonPlumeDrop `FlareBoot`.
abstract final class TideBoot {
  static bool productionReady = false;
  static Future<void>? _warmFuture;

  /// Idempotent — a cached result is returned after the first success.
  static Future<void> ensureProduction() =>
      _warmFuture ??= _warm().whenComplete(() {
        if (!productionReady) _warmFuture = null;
      });

  static Future<void> _warm() async {
    if (productionReady) return;
    if (!GleamHorizonConfig.grayCredentialsReady) {
      assert(() {
        debugPrint('[HZ.BOOT] gray gate DISABLED — white part only');
        return true;
      }());
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      productionReady = true;
      FirebaseMessaging.onBackgroundMessage(gleamBackgroundMessage);
      assert(() {
        debugPrint('[HZ.BOOT] Firebase.initializeApp OK');
        return true;
      }());
    } catch (error) {
      assert(() {
        debugPrint('[HZ.BOOT] Firebase.initializeApp failed: $error');
        return true;
      }());
      return;
    }
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
}
