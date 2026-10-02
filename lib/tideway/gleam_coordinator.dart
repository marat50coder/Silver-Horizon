import 'dart:async';
import 'dart:io';

import 'config/gleam_horizon_config.dart';
import 'core/gleam_models.dart';
import 'infra/gleam_attribution.dart';
import 'infra/gleam_exchange.dart';
import 'infra/gleam_route_reader.dart';
import 'infra/horizon_agent.dart';
import 'infra/horizon_beacon.dart';
import 'infra/horizon_vault.dart';
import 'infra/signal_reach.dart';

class GleamCoordinator {
  GleamCoordinator({
    required this.vault,
    required this.probe,
    required this.attribution,
    required this.exchange,
    required this.notifications,
    required this.agent,
    required this.runtimeEnabled,
  });

  final HorizonVault vault;
  final SignalReach probe;
  final GleamAttribution attribution;
  final GleamExchange exchange;
  final HorizonBeacon notifications;
  final HorizonAgent agent;
  final bool runtimeEnabled;

  bool get enabled => runtimeEnabled && GleamHorizonConfig.grayCredentialsReady;

  Future<TideDestination>? _decideFuture;

  Future<TideDestination> decide({
    required void Function(double value) onProgress,
  }) =>
      _decideFuture ??= _decide(onProgress: onProgress)
          .whenComplete(() => _decideFuture = null);

  Future<TideDestination> _decide({
    required void Function(double value) onProgress,
  }) async {
    if (!enabled) {
      assert(() {
        // ignore: avoid_print
        print(
          '[HZ.GLEAM] gate disabled '
          'runtime=$runtimeEnabled creds=${GleamHorizonConfig.grayCredentialsReady}',
        );
        return true;
      }());
      onProgress(1);
      return const NativeTide();
    }

    assert(() {
      // ignore: avoid_print
      print('[HZ.GLEAM] decide start route=${vault.route}');
      return true;
    }());

    notifications.onTokenChanged = _refreshForToken;
    // Pull the tap URL from SceneDelegate AND FCM before any cached first
    // page is considered. Otherwise a killed-app push opens the partner
    // homepage instead of the notification destination.
    await notifications.ingestLaunchPush();
    final sceneRoute = await GleamRouteReader.consume();
    final fcmRoute = await vault.consumePushUrl();
    final pushRoute = (sceneRoute != null && sceneRoute.isNotEmpty)
        ? sceneRoute
        : ((fcmRoute != null && fcmRoute.isNotEmpty) ? fcmRoute : null);
    if (pushRoute != null) {
      await vault.saveRoute(TideRoute.portal);
      unawaited(_backgroundDispatch());
      onProgress(1);
      return PortalTide(pushRoute, coldLaunch: sceneRoute != null);
    }

    onProgress(0.14);
    return switch (vault.route) {
      TideRoute.undecided => _firstDecision(onProgress),
      TideRoute.portal => _returningPortal(onProgress),
      TideRoute.native => _returningNative(onProgress),
    };
  }

  Future<TideDestination> _firstDecision(
    void Function(double) progress,
  ) async {
    // Mirror Tower_Breaker `_first()`: on a brand-new install with no
    // network, DO NOT flash a no-wifi page. Open the native game and
    // leave the route undecided so the next launch (hopefully online)
    // can run attribution and open the gray part. Flashing
    // QuietTidePage on fresh OneLink installs was reported as a
    // phantom no-wifi window on perfectly online cold starts — the
    // DNS probe at this stage mis-fires on cold-boot resolver latency.
    if (!await probe.hasInterface()) {
      assert(() {
        // ignore: avoid_print
        print('[HZ.GLEAM] first: no interface → native (silent)');
        return true;
      }());
      return const NativeTide();
    }
    progress(0.26);
    if (!await probe.canReachNetwork(
      perHostTimeout: const Duration(milliseconds: 1800),
      attempts: 2,
      retryDelay: const Duration(milliseconds: 500),
    )) {
      assert(() {
        // ignore: avoid_print
        print('[HZ.GLEAM] first: DNS probe failed → native (silent)');
        return true;
      }());
      return const NativeTide();
    }
    progress(0.44);
    // Warm push in parallel with attribution — the ATT prompt is what the
    // user expects to see first and APNs registration has no reason to delay
    // it (lesson #26).
    await Future.wait<void>(<Future<void>>[
      notifications.boot().catchError((_) {}),
      attribution.awaitSignals(),
    ]);
    progress(0.76);
    final reply = await _requestConfig();
    progress(1);
    assert(() {
      // ignore: avoid_print
      print(
        '[HZ.GLEAM] first: config hasDest=${reply.hasDestination} '
        'url=${reply.url}',
      );
      return true;
    }());
    if (reply.hasDestination) {
      await vault.saveRoute(TideRoute.portal);
      // Record the fact that this install belongs to the gray funnel so
      // future launches can keep promoting Organic→Non-organic even
      // after AppsFlyer stops surfacing the deferred deep-link payload.
      await vault.markGrayAttributed();
      return PortalTide(reply.url!);
    }
    // Mirror the Tower_Breaker _first() flow: lock the route to native
    // once the server has spoken, regardless of whether an af_status
    // actually arrived. The "undecided + retry on next cold start"
    // trick was swallowing legitimate OneLink installs where the first
    // POST happened before AppsFlyer finished its handshake — the gate
    // then stayed open forever and the WebView never opened on the
    // ONLY launch that was still eligible to show it. Returning native
    // + saving the route is the closed-form behaviour that TB ships.
    await vault.saveRoute(TideRoute.native);
    return const NativeTide();
  }

  Future<TideDestination> _returningPortal(
    void Function(double) progress,
  ) async {
    if (!await probe.hasInterface()) {
      return const OfflineTide(returnToNative: false);
    }
    await notifications.ingestLaunchPush();
    final pending = await vault.consumePushUrl() ??
        await GleamRouteReader.consume();
    if (pending != null && pending.isNotEmpty) {
      progress(1);
      return PortalTide(pending);
    }
    final cached = await vault.savedUrl();
    if (cached != null && !vault.cachedUrlExpired) {
      progress(1);
      return PortalTide(cached);
    }

    // Lesson from first-launch flow: never start AppsFlyer / fire the config
    // POST before we actually have reachability. The SDK will otherwise race
    // against DNS failure and submit an empty-attribution body.
    if (!await probe.canReachNetwork()) {
      return const OfflineTide(returnToNative: false);
    }
    await Future.wait<void>(<Future<void>>[
      notifications.boot(),
      attribution.start(),
    ]);
    progress(0.64);
    await attribution.awaitSignals(
      installTimeout: const Duration(seconds: 6),
    );
    final reply = await _requestConfig();
    progress(1);
    if (reply.hasDestination) return PortalTide(reply.url!);
    if (cached != null) return PortalTide(cached);
    return const OfflineTide(returnToNative: false);
  }

  Future<TideDestination> _returningNative(
    void Function(double) progress,
  ) async {
    if (!await probe.hasInterface()) {
      progress(1);
      return const NativeTide();
    }
    // Defer AppsFlyer startup until reachability is proven, otherwise the
    // SDK races against DNS and sends an empty attribution.
    if (!await probe.canReachNetwork()) {
      progress(1);
      return const NativeTide();
    }
    await Future.wait<void>(<Future<void>>[
      notifications.boot(),
      attribution.start(),
    ]);
    progress(0.58);
    await attribution.awaitSignals();
    final reply = await _requestConfig();
    progress(1);
    if (!reply.hasDestination) return const NativeTide();
    await vault.saveRoute(TideRoute.portal);
    return PortalTide(reply.url!);
  }

  Future<GleamReply> _requestConfig({String? token}) async {
    final body = await attribution.compose(
      locale: Platform.localeName.replaceAll('-', '_'),
      pushToken: token ?? notifications.token,
      // Sticky-promote Organic→Non-organic once we have ever opened the
      // gray part. AppsFlyer only exposes `deep_link_value` on the install
      // launch, so without this flag a re-open loses the attribution.
      stickyGrayAttribution:
          vault.grayAttributed || vault.route == TideRoute.portal,
    );
    if (GleamHorizonConfig.debugForcePortal) {
      body['af_status'] = 'Non-organic';
      body['af_message'] = 'force_portal';
      assert(() {
        // ignore: avoid_print
        print('[HZ.GLEAM] FORCE_PORTAL → af_status=Non-organic');
        return true;
      }());
    }
    return exchange.request(body);
  }

  Future<void> _backgroundDispatch() async {
    try {
      await Future.wait<void>(<Future<void>>[
        notifications.boot(),
        attribution.awaitSignals(),
      ]);
      await _requestConfig();
    } catch (_) {}
  }

  Future<void> _refreshForToken(String token) async {
    if (!attribution.sawAttribution) return;
    try {
      await _requestConfig(token: token);
    } catch (_) {}
  }
}
