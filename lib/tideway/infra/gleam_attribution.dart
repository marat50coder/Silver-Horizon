import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/gleam_horizon_config.dart';
import 'horizon_agent.dart';

void gleamTrace(String Function() message) {
  assert(() {
    debugPrint(message());
    return true;
  }());
}

class GleamAttribution {
  GleamAttribution(this._agent);

  final HorizonAgent _agent;
  AppsflyerSdk? _sdk;
  Map<String, dynamic>? _install;
  Map<String, dynamic>? _reopen;
  Map<String, dynamic>? _deepLink;
  Future<void>? _startFuture;
  Future<void>? _consentFuture;
  final Completer<void> _installReady = Completer<void>();
  final Completer<void> _deepLinkReady = Completer<void>();

  /// ATT consent prompt — memoized SEPARATELY from the SDK start so that if
  /// the prompt is lost because the app wasn't frontmost (lesson #26) a later
  /// pipeline run can retry it. The SDK start awaits the same future, so
  /// nothing asks twice.
  Future<void> requestConsent() => _consentFuture ??= _promptForConsent();

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (!GleamHorizonConfig.grayCredentialsReady) {
      _completeEmpty();
      return;
    }
    try {
      await requestConsent();
      final sdk = AppsflyerSdk(
        AppsFlyerOptions(
          afDevKey: GleamHorizonConfig.appsFlyerKey,
          appId: GleamHorizonConfig.iosStoreId,
          showDebug: kDebugMode,
          timeToWaitForATTUserAuthorization:
              GleamHorizonConfig.attWaitSeconds.toDouble(),
        ),
      );
      _sdk = sdk;
      sdk.onInstallConversionData(_acceptInstall);
      sdk.onAppOpenAttribution((raw) => _reopen = _flat(raw));
      sdk.onDeepLinking((result) {
        final event = result.deepLink?.clickEvent;
        if (event != null) _deepLink = Map<String, dynamic>.from(event);
        if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
      });
      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (error) {
      gleamTrace(() => '[HZ.TIDE] initialization failed: $error');
      _completeEmpty();
    }
  }

  Future<void> _promptForConsent() async {
    if (!Platform.isIOS) return;
    var status =
        await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status != TrackingStatus.notDetermined) {
      _consentFuture = Future<void>.value();
      return;
    }
    await _waitForFrontmost();
    await Future<void>.delayed(
      const Duration(milliseconds: GleamHorizonConfig.attPromptDelayMs),
    );
    status = await AppTrackingTransparency.requestTrackingAuthorization();
    if (status == TrackingStatus.notDetermined) {
      // Lost — the prompt wasn't actually shown (app not frontmost yet).
      // Clear the memoized future so the pipeline can call again later.
      _consentFuture = null;
      await _waitForFrontmost();
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }

  Future<void> _waitForFrontmost() async {
    await WidgetsBinding.instance.endOfFrame;
    // Lifecycle `null` is reported late on a cold start — treat it as
    // frontmost per lesson #26. Only `paused` / `inactive` mean "wait".
    final binding = WidgetsBinding.instance;
    for (var i = 0; i < 10; i++) {
      final state = binding.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<void> _acceptInstall(dynamic raw) async {
    try {
      final received = _flat(raw);
      final status = received['status']?.toString().toLowerCase();
      final failed = status == 'failure' ||
          (received['af_status'] == null && received.containsKey('status'));
      gleamTrace(
        () => '[HZ.TIDE] conversion status=$status '
            'af_status=${received['af_status']} keys=${received.keys.toList()}',
      );
      if (failed) {
        _install = <String, dynamic>{};
      } else if (received['af_status'] == 'Organic') {
        // Publish immediately. A delayed GCD poll must not hold the
        // completer: the splash used to time out and POST with no af_status.
        _install = received;
        final late = await _fetchGcd();
        if (late != null &&
            late['af_status'] != null &&
            late['af_status'] != 'Organic') {
          _install = late;
        }
      } else {
        _install = received;
      }
    } catch (error) {
      gleamTrace(() => '[HZ.TIDE] conversion parse error: $error');
      _install = <String, dynamic>{};
    } finally {
      if (!_installReady.isCompleted) _installReady.complete();
    }
  }

  Map<String, dynamic> _flat(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final map = Map<String, dynamic>.from(raw);
    final payload = map['payload'];
    return payload is Map ? Map<String, dynamic>.from(payload) : map;
  }

  Future<Map<String, dynamic>?> _fetchGcd() async {
    final uid = await appsFlyerId();
    if (uid == null || uid.isEmpty) return null;
    try {
      final base = GleamHorizonConfig.gcdBase;
      final sep = base.contains('?') ? '&' : '?';
      final uri = Uri.parse(
        '$base${sep}app_id=${GleamHorizonConfig.iosStoreId}&device_id=$uid',
      );
      final response = await _agent
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer ${GleamHorizonConfig.appsFlyerKey}',
            },
          )
          .timeout(
            const Duration(seconds: GleamHorizonConfig.gcdTimeoutSeconds),
          );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> awaitSignals({
    Duration installTimeout = const Duration(
      seconds: GleamHorizonConfig.installSignalSeconds,
    ),
  }) async {
    await start();
    await Future.wait<void>(<Future<void>>[
      _installReady.future.timeout(installTimeout, onTimeout: () {}),
      _deepLinkReady.future.timeout(
        const Duration(seconds: GleamHorizonConfig.deepLinkSeconds),
        onTimeout: () {},
      ),
    ]);
  }

  /// True once install conversion actually arrived. A timed-out wait leaves
  /// this false — the coordinator must not lock the native route on that.
  bool get sawAttribution =>
      _install != null && _install!.containsKey('af_status');

  Future<String?> appsFlyerId() async {
    try {
      return await _sdk?.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> compose({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    if (_install != null) body.addAll(_install!);
    if (_reopen != null) {
      _reopen!.forEach((key, value) => body.putIfAbsent(key, () => value));
    }
    if (_deepLink != null) {
      _deepLink!.forEach((key, value) => body.putIfAbsent(key, () => value));
    }

    body['af_id'] = await appsFlyerId() ?? body['af_id'] ?? '';
    body['bundle_id'] = GleamHorizonConfig.bundleId;
    body['os'] = 'iOS';
    body['store_id'] = GleamHorizonConfig.storeToken;
    body['locale'] = locale;
    if (pushToken != null &&
        pushToken.isNotEmpty &&
        GleamHorizonConfig.firebaseProjectNumber.isNotEmpty) {
      body['push_token'] = pushToken;
      body['firebase_project_id'] = GleamHorizonConfig.firebaseProjectNumber;
    }

    if (Platform.isIOS) {
      try {
        if (await AppTrackingTransparency.trackingAuthorizationStatus ==
            TrackingStatus.authorized) {
          final idfa = await AppTrackingTransparency.getAdvertisingIdentifier();
          if (idfa.isNotEmpty && !idfa.startsWith('00000000-')) {
            body['sub_id_10'] = idfa;
          }
        }
      } catch (_) {}
    }
    gleamTrace(() => '[HZ.TIDE] payload ${jsonEncode(body)}');
    return body;
  }

  void _completeEmpty() {
    if (!_installReady.isCompleted) _installReady.complete();
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }
}
