import 'dart:async';
// `unawaited` lives in dart:async in modern SDKs.
import 'dart:convert';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/gleam_horizon_config.dart';
import 'horizon_agent.dart';
import 'horizon_vault.dart';

void gleamTrace(String Function() message) {
  assert(() {
    debugPrint(message());
    return true;
  }());
}

class GleamAttribution {
  GleamAttribution(this._agent, {HorizonVault? vault})
      // Named + nullable: prefer_initializing_formals doesn't apply.
      // ignore: prefer_initializing_formals
      : _vault = vault;

  final HorizonAgent _agent;
  final HorizonVault? _vault;
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
      // Fire the ATT prompt in parallel with the SDK init — AppsFlyer's
      // native `timeToWaitForATTUserAuthorization` already holds back the
      // install event until the user responds (or the timeout expires).
      // Awaiting the prompt before `AppsflyerSdk(...)` was double-counting
      // that wait and routinely truncated the OneLink conversion window
      // on cold start, so the SDK then reported `Organic` for a real
      // Non-organic install — exactly the "doesn't let into the gray
      // part" symptom. Tower_Breaker lets the SDK own the wait.
      unawaited(requestConsent());
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
      sdk.onAppOpenAttribution((raw) {
        _reopen = _normalize(_flat(raw));
        if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
      });
      sdk.onDeepLinking((result) {
        final event = result.deepLink?.clickEvent;
        gleamTrace(
          () => '[HZ.TIDE] udl status=${result.status} '
              'keys=${event?.keys.toList()}',
        );
        if (event != null && event.isNotEmpty) {
          _deepLink = _normalize(Map<String, dynamic>.from(event));
        }
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
      final received = _normalize(_flat(raw));
      final status = received['status']?.toString().toLowerCase();
      final failed = status == 'failure' ||
          (received['af_status'] == null && received.containsKey('status'));
      gleamTrace(
        () => '[HZ.TIDE] conversion status=$status '
            'af_status=${received['af_status']} keys=${received.keys.toList()}',
      );
      if (failed) {
        _install ??= <String, dynamic>{};
      } else {
        // A later Organic / thin callback (is_first_launch=0) must not
        // wipe a Non-organic row we already stored — that is how campaign
        // / af_sub* used to disappear from the config POST on re-open.
        _install = _preferRicher(_install, received);
        if (!_isPaid(_install) && received['af_status'] == 'Organic') {
          // Rescue runs in the background. Blocking the install completer
          // here starves `awaitSignals` for 6+ seconds and the pipeline
          // then composes with an empty body on flaky networks.
          unawaited(_rescuePaidInBackground(received));
        }
      }
    } catch (error) {
      gleamTrace(() => '[HZ.TIDE] conversion parse error: $error');
      _install ??= <String, dynamic>{};
    } finally {
      if (!_installReady.isCompleted) _installReady.complete();
    }
  }

  bool _isBlank(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    if (text.isEmpty) return true;
    final lower = text.toLowerCase();
    return lower == 'null' || lower == '<null>' || lower == 'nil';
  }

  bool _isPaid(Map<String, dynamic>? map) {
    final status = map?['af_status']?.toString();
    return status != null && status.isNotEmpty && status != 'Organic';
  }

  /// Drop AF placeholders and copy OneLink aliases (pid → media_source,
  /// c → campaign) so config.php sees the same keys the dashboard uses.
  Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (_isBlank(value)) return;
      out[key] = value;
    });
    void alias(String from, String to) {
      final value = out[from];
      if (_isBlank(value)) return;
      if (_isBlank(out[to])) out[to] = value;
    }

    alias('pid', 'media_source');
    alias('c', 'campaign');
    alias('af_channel', 'media_source');
    alias('af_adset', 'adset');
    alias('af_c_id', 'campaign_id');
    alias('af_siteid', 'siteid');
    return out;
  }

  Map<String, dynamic> _preferRicher(
    Map<String, dynamic>? current,
    Map<String, dynamic> incoming,
  ) {
    if (current == null || current.isEmpty) return incoming;
    // Already paid, new one is organic / thin → keep paid status, fold in
    // only blank slots.
    if (_isPaid(current) && !_isPaid(incoming)) {
      final merged = Map<String, dynamic>.from(current);
      incoming.forEach((key, value) {
        if (key == 'af_status' || key == 'af_message') return;
        if (_isBlank(merged[key]) && !_isBlank(value)) merged[key] = value;
      });
      return merged;
    }
    final merged = Map<String, dynamic>.from(current);
    incoming.forEach((key, value) {
      if (_isBlank(value)) return;
      if (key == 'af_status' && _isPaid(current) && !_isPaid(incoming)) {
        return;
      }
      if (_isBlank(merged[key]) || key == 'af_status' || key == 'af_message') {
        merged[key] = value;
      } else if (value.toString().length > merged[key].toString().length) {
        if (key == 'campaign' ||
            key == 'media_source' ||
            key.startsWith('af_sub') ||
            key.startsWith('deep_link')) {
          merged[key] = value;
        }
      }
    });
    return merged;
  }

  Future<void> _rescuePaidInBackground(Map<String, dynamic> organic) async {
    for (var pass = 0; pass < 3; pass++) {
      await Future<void>.delayed(
        Duration(
          seconds: GleamHorizonConfig.organicRecheckSeconds + pass * 4,
        ),
      );
      final gcd = await _fetchGcd();
      if (gcd == null || gcd.isEmpty) continue;
      final status = gcd['af_status']?.toString();
      if (status == null || status.isEmpty) continue;
      final normalised = _normalize(gcd);
      _install = _preferRicher(_install, normalised);
      gleamTrace(
        () => '[HZ.TIDE] gcd pass=$pass af_status=$status '
            'install=${_install?['af_status']}',
      );
      if (status != 'Organic') return;
    }
  }

  /// Writes [value] into `data[key]` only when the current value is null or
  /// an empty string. Used to lift `deep_link_sub*` into the `af_sub*` /
  /// `campaign` slots that the server reads for partner routing.
  static void _mergeMissing(
    Map<String, dynamic> into,
    Map<String, dynamic> from,
  ) {
    from.forEach((key, value) => _hoistIfEmpty(into, key, value));
  }

  static bool _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty;

  /// The backend reads `campaign` / `af_sub*` / `media_source`. A OneLink
  /// often delivers those only as `deep_link_*`, and an empty string already
  /// sitting in the conversion map must not block the real value.
  static void _hoistPartnerSlots(Map<String, dynamic> body) {
    _hoistIfEmpty(body, 'campaign', body['deep_link_value']);
    _hoistIfEmpty(body, 'campaign_id', body['deep_link_value']);
    _hoistIfEmpty(body, 'af_sub1', body['deep_link_sub1']);
    _hoistIfEmpty(body, 'af_sub2', body['deep_link_sub2']);
    _hoistIfEmpty(body, 'af_sub3', body['deep_link_sub3']);
    _hoistIfEmpty(body, 'af_sub4', body['deep_link_sub4']);
    _hoistIfEmpty(body, 'af_sub5', body['deep_link_sub5']);
    if (_nonEmpty(body['deep_link_value']) ||
        _nonEmpty(body['campaign']) ||
        _nonEmpty(body['af_sub1'])) {
      _hoistIfEmpty(body, 'media_source', 'af_dynamic_onelink');
    }
  }

  static const Set<String> _identityKeys = <String>{
    'af_id',
    'bundle_id',
    'os',
    'store_id',
    'locale',
    'push_token',
    'firebase_project_id',
    'sub_id_10',
  };

  Future<void> _rememberPartners(Map<String, dynamic> body) async {
    final vault = _vault;
    if (vault == null) return;
    final memo = await vault.readAttributionMemo() ?? <String, String>{};
    body.forEach((key, value) {
      if (_identityKeys.contains(key) || value == null) return;
      final text = value is String ? value.trim() : value.toString().trim();
      if (text.isEmpty || text == 'null') return;
      final current = memo[key];
      if (current == null || current.isEmpty) memo[key] = text;
    });
    if (memo.isEmpty) return;
    await vault.writeAttributionMemo(memo);
  }

  static void _hoistIfEmpty(Map<String, dynamic> data, String key, Object? value) {
    if (value == null) return;
    if (value is String && value.trim().isEmpty) return;
    final current = data[key];
    if (current == null || (current is String && current.trim().isEmpty)) {
      data[key] = value;
    }
  }

  /// A OneLink / tracking-link install that was matched probabilistically
  /// instead of by IDFA. AppsFlyer flags such installs as `Organic` on iOS
  /// whenever ATT is denied or unavailable, but the deep-link fields prove
  /// the user actually came through our funnel.
  bool _looksLikeProbabilisticOneLink(Map<String, dynamic> data) {
    bool nonEmpty(Object? value) =>
        value is String && value.trim().isNotEmpty;

    final deferred = data['is_deferred'] == true ||
        data['is_deferred']?.toString().toLowerCase() == 'true';
    final matchType = data['match_type']?.toString().toLowerCase() ?? '';
    final probabilistic = matchType.contains('probabilistic') ||
        matchType.contains('fingerprint');

    final hasDeepLink = nonEmpty(data['deep_link_value']) ||
        nonEmpty(data['deep_link_sub1']) ||
        nonEmpty(data['deep_link_sub2']) ||
        nonEmpty(data['deep_link_sub3']) ||
        nonEmpty(data['deep_link_sub4']) ||
        nonEmpty(data['deep_link_sub5']);

    final hasCampaign = nonEmpty(data['campaign']) ||
        nonEmpty(data['campaign_id']) ||
        nonEmpty(data['media_source']) ||
        nonEmpty(data['af_siteid']) ||
        nonEmpty(data['af_c_id']);

    // Any one of: deferred flag, a non-empty deep-link value, a probabilistic
    // match type, or a filled campaign slot is enough to say "this install
    // came through our funnel, not from a cold search on the App Store".
    return deferred || hasDeepLink || hasCampaign || probabilistic;
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
    bool stickyGrayAttribution = false,
  }) async {
    final body = <String, dynamic>{};
    if (_install != null) body.addAll(_normalize(_install!));
    // `_mergeMissing` fills only blanks and never lets `campaign: ""`
    // block a real OneLink value. Each source is normalized first so
    // placeholders ("<null>", "nil") never reach the POST either.
    if (_reopen != null) _mergeMissing(body, _normalize(_reopen!));
    if (_deepLink != null) _mergeMissing(body, _normalize(_deepLink!));

    // AppsFlyer does not re-emit onDeepLinking after the install launch.
    // The memo is the only copy of deep_link_sub* / campaign on a re-open.
    if (_vault != null) {
      final memo = await _vault.readAttributionMemo();
      if (memo != null) {
        _mergeMissing(body, _normalize(Map<String, dynamic>.from(memo)));
      }
    }

    // AppsFlyer labels every install without a deterministic ID match
    // (IDFA / Apple Search Ads token) as `Organic`. A real OneLink click
    // can still have landed with `match_type=probabilistic` or a non-empty
    // `deep_link_value` — the deep-link fields live in `_deepLink` and
    // only become visible once all three sources are merged, which is why
    // the promotion runs here and not in `_acceptInstall`. The server gate
    // trusts only `af_status`; leaving it as Organic sends every
    // ATT-denied OneLink install into the white part.
    //
    // `stickyGrayAttribution` is set by the coordinator once a previous
    // launch successfully opened the gray part. AppsFlyer's deferred
    // deep-link callback (`onDeepLinking`) only fires on the install
    // launch, so a plain re-open would otherwise lose `deep_link_value`
    // and the promotion gate would close — the user would see the
    // native game on launch 2 even though the install is non-organic.
    _hoistPartnerSlots(body);
    final status = body['af_status']?.toString().toLowerCase();
    final promote = stickyGrayAttribution ||
        _looksLikeProbabilisticOneLink(body) ||
        _nonEmpty(body['deep_link_value']);
    if (promote && status != 'non-organic') {
      final before = body['af_status'];
      body['af_status'] = 'Non-organic';
      body['af_message'] =
          'probabilistic_onelink (${body['match_type'] ?? 'unknown'})';
      _hoistIfEmpty(body, 'media_source', 'af_dynamic_onelink');
      gleamTrace(
        () => '[HZ.TIDE] promoted $before → Non-organic '
            'sticky=$stickyGrayAttribution '
            'deep_link_value=${body['deep_link_value']} '
            'campaign=${body['campaign']} '
            'media_source=${body['media_source']} '
            'af_sub1=${body['af_sub1']}',
      );
    }
    await _rememberPartners(body);

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
