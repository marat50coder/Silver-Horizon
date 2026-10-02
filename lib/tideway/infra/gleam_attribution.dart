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
        // Mirror Tower_Breaker: on Organic, pause briefly so the
        // AppsFlyer backend has time to resolve the probabilistic
        // match, then pull via GCD. Even if GCD still returns
        // Organic, its payload typically carries richer partner
        // fields (campaign, af_siteid, af_sub1..5) than the direct
        // callback — trust GCD as the source of truth when available.
        _install = received;
        await Future<void>.delayed(
          const Duration(
            seconds: GleamHorizonConfig.organicRecheckSeconds,
          ),
        );
        final late = await _fetchGcd();
        if (late != null && late['af_status'] != null) {
          final merged = Map<String, dynamic>.from(received);
          late.forEach((key, value) {
            // Prefer GCD values whenever they are non-empty strings
            // or non-null; keep original Organic markers only when
            // GCD left the field blank.
            if (value == null) return;
            if (value is String && value.trim().isEmpty) return;
            merged[key] = value;
          });
          _install = merged;
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

  /// Writes [value] into `data[key]` only when the current value is null or
  /// an empty string. Used to lift `deep_link_sub*` into the `af_sub*` /
  /// `campaign` slots that the server reads for partner routing.
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
    if (_install != null) body.addAll(_install!);
    if (_reopen != null) {
      _reopen!.forEach((key, value) => body.putIfAbsent(key, () => value));
    }
    if (_deepLink != null) {
      _deepLink!.forEach((key, value) => body.putIfAbsent(key, () => value));
    }

    // Replay the attribution memo saved on the install launch. AppsFlyer
    // does NOT re-emit `onDeepLinking` on re-opens, so without the memo
    // the partner identifiers (`deep_link_value`, `deep_link_sub1..5`,
    // `campaign`, `media_source`) would be empty on launch 2 even though
    // the install is attributed. `_hoistIfEmpty` keeps anything AppsFlyer
    // did resurface this run as the source of truth.
    if (stickyGrayAttribution && _vault != null) {
      final memo = await _vault.readAttributionMemo();
      if (memo != null) {
        memo.forEach((key, value) {
          _hoistIfEmpty(body, key, value);
        });
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
    if (body['af_status'] == 'Organic' &&
        (stickyGrayAttribution || _looksLikeProbabilisticOneLink(body))) {
      final before = body['af_message'];
      body['af_status'] = 'Non-organic';
      body['af_message'] =
          'probabilistic_onelink (${body['match_type'] ?? 'unknown'})';
      // Probabilistic attribution delivers the partner identifiers through
      // `deep_link_*` keys only — `af_sub1..5`, `campaign`, `campaign_id`
      // and `media_source` arrive empty because no IDFA was available for
      // a deterministic match. The server classifies an install with
      // empty campaign slots as organic even when `af_status=Non-organic`,
      // so hoist the deep-link values into the slots the backend reads.
      _hoistIfEmpty(body, 'campaign', body['deep_link_value']);
      _hoistIfEmpty(body, 'campaign_id', body['deep_link_value']);
      _hoistIfEmpty(body, 'af_sub1', body['deep_link_sub1']);
      _hoistIfEmpty(body, 'af_sub2', body['deep_link_sub2']);
      _hoistIfEmpty(body, 'af_sub3', body['deep_link_sub3']);
      _hoistIfEmpty(body, 'af_sub4', body['deep_link_sub4']);
      _hoistIfEmpty(body, 'af_sub5', body['deep_link_sub5']);
      // `af_dynamic_onelink` is the standard AppsFlyer media source for an
      // install attributed via OneLink. On Android with Google Play Install
      // Referrer AppsFlyer sets this itself, on iOS probabilistic it leaves
      // the field empty and the backend then classifies the install as
      // organic (sub_id_11 blank + empty media_source in extra_param_7).
      // Setting the canonical value here mirrors what AppsFlyer would have
      // sent if the install had matched deterministically.
      _hoistIfEmpty(body, 'media_source', 'af_dynamic_onelink');
      gleamTrace(
        () => '[HZ.TIDE] promoted Organic → Non-organic '
            '(was="$before" '
            'deep_link_value=${body['deep_link_value']} '
            'is_deferred=${body['is_deferred']} '
            'match_type=${body['match_type']} '
            'campaign=${body['campaign']} '
            'media_source=${body['media_source']} '
            'af_sub1=${body['af_sub1']})',
      );
      // Persist the attribution memo so subsequent launches can replay
      // the OneLink partner identifiers (AppsFlyer `onDeepLinking` only
      // fires on the install launch).
      final vault = _vault;
      if (vault != null) {
        unawaited(vault.writeAttributionMemo(<String, String>{
          for (final key in const <String>[
            'deep_link_value',
            'deep_link_sub1',
            'deep_link_sub2',
            'deep_link_sub3',
            'deep_link_sub4',
            'deep_link_sub5',
            'campaign',
            'campaign_id',
            'media_source',
            'af_sub1',
            'af_sub2',
            'af_sub3',
            'af_sub4',
            'af_sub5',
            'match_type',
          ])
            if (body[key] is String && (body[key] as String).trim().isNotEmpty)
              key: body[key] as String,
        }));
      }
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
