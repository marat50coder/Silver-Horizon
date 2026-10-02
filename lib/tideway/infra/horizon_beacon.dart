import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'horizon_vault.dart';

/// Keys that may hold the destination URL inside a push payload. Must stay
/// in sync with the Swift list in `SceneDelegate.urlKeys`. The lookup is
/// case-insensitive, so `clickURL`, `Click_Url` and `CLICKURL` all match.
const List<String> _pushUrlKeys = <String>[
  'click_url', 'clickurl',
  'deep_link', 'deeplink',
  'target_url', 'target',
  'destination', 'dest',
  'url', 'link', 'href',
  'open_url', 'landing_url', 'offer_url',
  'redirect_url', 'action_url', 'web_url',
];

@pragma('vm:entry-point')
Future<void> gleamBackgroundMessage(RemoteMessage _) async {}

class HorizonBeacon {
  HorizonBeacon(this._vault, {required this.enabled});

  final HorizonVault _vault;
  final bool enabled;
  FirebaseMessaging? _messaging;
  Future<void>? _bootFuture;
  Future<bool>? _permissionFuture;
  String? _token;

  void Function(String url)? onDestination;
  void Function(String token)? onTokenChanged;

  String? get token => _token;

  Future<void> boot() => _bootFuture ??= _boot();

  /// Stash a cold-start / tap payload without waiting for APNs.
  /// Safe to call before reachability — it only reads the local FCM cache.
  Future<void> ingestLaunchPush() async {
    if (!enabled) return;
    final messaging = FirebaseMessaging.instance;
    _messaging ??= messaging;
    if (!_openedAppBound) {
      _openedAppBound = true;
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    }
    try {
      final initial = await messaging.getInitialMessage().timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      final initialUrl = initial == null ? null : _extract(initial.data);
      if (initialUrl != null) await _vault.stashPushUrl(initialUrl);
    } catch (_) {}
  }

  bool _openedAppBound = false;

  void _handleOpenedMessage(RemoteMessage message) {
    final url = _extract(message.data);
    if (url == null) return;
    final callback = onDestination;
    if (callback == null) {
      _vault.stashPushUrl(url);
    } else {
      callback(url);
    }
  }

  Future<void> _boot() async {
    if (!enabled) return;
    final messaging = FirebaseMessaging.instance;
    _messaging = messaging;
    await ingestLaunchPush();

    FirebaseMessaging.onBackgroundMessage(gleamBackgroundMessage);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    messaging.onTokenRefresh.listen((value) {
      _token = value;
      onTokenChanged?.call(value);
    });
    await _waitForApns();
    _token = await messaging.getToken();
  }

  String? _extract(Map<String, dynamic> payload) => _urlFromAny(payload);

  static String? _urlFromAny(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
      // Some backends ship nested JSON blobs as strings (e.g.
      // `data: "{\"click_url\":\"https://...\"}"`). Try to decode and recurse.
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return _urlFromAny(jsonDecode(trimmed));
        } catch (_) {}
      }
      return null;
    }
    if (value is Map) {
      // Lowercase lookup table so clickURL / Click_Url / CLICKURL all match.
      final lower = <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString().toLowerCase(): entry.value,
      };
      for (final key in _pushUrlKeys) {
        final hit = _urlFromAny(lower[key]);
        if (hit != null) return hit;
      }
      // Recurse into every nested value — covers `data`, `payload`, `aps`,
      // and any custom container the backend decides to use.
      for (final child in value.values) {
        final hit = _urlFromAny(child);
        if (hit != null) return hit;
      }
      return null;
    }
    if (value is List) {
      for (final item in value) {
        final hit = _urlFromAny(item);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  Future<void> _waitForApns({int attempts = 7}) async {
    final messaging = _messaging;
    if (messaging == null) return;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        if ((await messaging.getAPNSToken())?.isNotEmpty ?? false) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 420));
    }
  }

  Future<bool> canOfferPermission() async {
    if (!enabled || _vault.pushDeniedByOs) return false;
    final messaging = _messaging;
    if (messaging == null) return false;
    final status =
        (await messaging.getNotificationSettings()).authorizationStatus;
    if (status == AuthorizationStatus.denied) {
      await _vault.markPushDeniedByOs();
      return false;
    }
    return status == AuthorizationStatus.notDetermined ||
        status == AuthorizationStatus.provisional;
  }

  Future<bool> askPermission() {
    return _permissionFuture ??= _performPermissionRequest().whenComplete(
      () => _permissionFuture = null,
    );
  }

  Future<bool> _performPermissionRequest() async {
    if (!enabled || _messaging == null) return false;
    final result = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final accepted =
        result.authorizationStatus == AuthorizationStatus.authorized ||
        result.authorizationStatus == AuthorizationStatus.provisional;
    await _vault.setPushAllowed(accepted);
    if (!accepted && result.authorizationStatus == AuthorizationStatus.denied) {
      await _vault.markPushDeniedByOs();
    }
    if (accepted) {
      // Resolve the APNs + FCM token in the BACKGROUND. Blocking the UI
      // on `_waitForApns(attempts: 12)` + `getToken()` after the user
      // tapped "Allow" was adding 3–6 s of spinner on the invitation
      // screen before the WebView could even mount — the user saw a
      // "very long loading" state right after the iOS prompt. The
      // token is non-essential for the first page open: when it
      // arrives, `onTokenRefresh` + `onTokenChanged` deliver it to the
      // coordinator, which re-POSTs the config endpoint. The server
      // keeps a slot for the token and binds it on the second POST.
      unawaited(_resolveTokenInBackground());
    }
    return accepted;
  }

  Future<void> _resolveTokenInBackground() async {
    try {
      await _waitForApns(attempts: 12);
      final value = await _messaging?.getToken();
      if (value != null && value.isNotEmpty) {
        _token = value;
        onTokenChanged?.call(value);
      }
    } catch (_) {}
  }
}
