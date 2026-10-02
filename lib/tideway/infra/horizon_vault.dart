import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/gleam_horizon_config.dart';
import '../core/gleam_models.dart';

class HorizonVault {
  static const String _routeKey = 'sh.gleam.route';
  static const String _expiryKey = 'sh.gleam.expiry';
  static const String _inviteKey = 'sh.gleam.invite.after';
  static const String _permissionKey = 'sh.gleam.push.allowed';
  static const String _osDeniedKey = 'sh.gleam.push.os_denied';
  static const String _savedUrlKey = 'sh.gleam.secure.destination';
  static const String _pendingUrlKey = 'sh.gleam.secure.pending';
  static const String _grayAttributedKey = 'sh.gleam.gray_attributed';
  static const String _attributionMemoKey = 'sh.gleam.secure.attr_memo';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  late SharedPreferences _preferences;

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  TideRoute get route => TideRoute.parse(_preferences.getString(_routeKey));

  Future<void> saveRoute(TideRoute route) =>
      _preferences.setString(_routeKey, route.storageValue);

  Future<String?> savedUrl() async {
    try {
      return await _secure.read(key: _savedUrlKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUrl(String url, int? expiresAt) async {
    try {
      await _secure.write(key: _savedUrlKey, value: url);
      // Reject server-sent `expires` values that are already in the past
      // or shorter than our default window. The production backend has
      // been observed shipping `expires` ~7 minutes BEFORE the current
      // time, which caused the cached URL to be marked expired the
      // moment it landed — the next cold start then skipped the fast
      // cached-URL path and fell through to a full POST round-trip.
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final defaultExpiry = nowSeconds +
          const Duration(days: GleamHorizonConfig.savedUrlExpiryDays).inSeconds;
      final serverExpiry = expiresAt ?? 0;
      final expiry =
          serverExpiry > defaultExpiry ? serverExpiry : defaultExpiry;
      await _preferences.setInt(_expiryKey, expiry);
    } catch (_) {}
  }

  /// True once at least one successful config POST classified the install
  /// as reachable through the gray flow. Set after the first launch that
  /// opens the WebView — the flag survives app restarts so subsequent
  /// launches can keep promoting Organic→Non-organic even when AppsFlyer
  /// no longer surfaces the deferred deep-link payload (that only
  /// resolves on the install launch itself).
  bool get grayAttributed => _preferences.getBool(_grayAttributedKey) ?? false;

  Future<void> markGrayAttributed() =>
      _preferences.setBool(_grayAttributedKey, true);

  /// Returns the serialized OneLink attribution memo stored on the install
  /// launch (`deep_link_value`, `deep_link_sub1..5`, `campaign`, `media_source`
  /// and friends). AppsFlyer's `onDeepLinking` callback only resolves on
  /// the install launch, so the memo is the only way to keep sending the
  /// partner identifiers on subsequent re-opens.
  Future<Map<String, String>?> readAttributionMemo() async {
    try {
      final raw = await _secure.read(key: _attributionMemoKey);
      if (raw == null || raw.isEmpty) return null;
      final parts = raw.split('\u0001');
      final result = <String, String>{};
      for (final chunk in parts) {
        final eq = chunk.indexOf('=');
        if (eq <= 0) continue;
        final key = chunk.substring(0, eq);
        final value = chunk.substring(eq + 1);
        if (value.isNotEmpty) result[key] = value;
      }
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeAttributionMemo(Map<String, String> values) async {
    final cleaned = <String, String>{
      for (final entry in values.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (cleaned.isEmpty) return;
    try {
      final encoded =
          cleaned.entries.map((e) => '${e.key}=${e.value}').join('\u0001');
      await _secure.write(key: _attributionMemoKey, value: encoded);
    } catch (_) {}
  }

  bool get cachedUrlExpired {
    final expiry = _preferences.getInt(_expiryKey);
    return expiry == null ||
        DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry;
  }

  Future<void> stashPushUrl(String url) async {
    if (url.trim().isEmpty) return;
    try {
      await _secure.write(key: _pendingUrlKey, value: url.trim());
    } catch (_) {}
  }

  Future<String?> consumePushUrl() async {
    try {
      final value = await _secure.read(key: _pendingUrlKey);
      if (value != null) await _secure.delete(key: _pendingUrlKey);
      return value;
    } catch (_) {
      return null;
    }
  }

  bool get pushAllowed => _preferences.getBool(_permissionKey) ?? false;
  bool get pushDeniedByOs => _preferences.getBool(_osDeniedKey) ?? false;

  Future<void> setPushAllowed(bool value) =>
      _preferences.setBool(_permissionKey, value);

  Future<void> markPushDeniedByOs() =>
      _preferences.setBool(_osDeniedKey, true);

  bool get shouldShowPushInvite {
    if (pushAllowed || pushDeniedByOs) return false;
    final after = _preferences.getInt(_inviteKey);
    return after == null ||
        DateTime.now().millisecondsSinceEpoch ~/ 1000 >= after;
  }

  Future<void> snoozePushInvite(int epochSeconds) =>
      _preferences.setInt(_inviteKey, epochSeconds);
}
