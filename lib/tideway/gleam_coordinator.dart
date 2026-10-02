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
    final coldRoute = await GleamRouteReader.consume();
    if (coldRoute != null) {
      await vault.saveRoute(TideRoute.portal);
      await vault.consumePushUrl();
      unawaited(_backgroundDispatch());
      onProgress(1);
      return PortalTide(coldRoute, coldLaunch: true);
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
    // Lesson #25: on the undecided route nothing network-dependent runs
    // before BOTH interface + real reachability pass. Only then do we warm
    // push + attribution (which triggers the ATT prompt).
    if (!await probe.hasInterface()) {
      assert(() {
        // ignore: avoid_print
        print('[HZ.GLEAM] first: no interface → offline');
        return true;
      }());
      return const OfflineTide(returnToNative: false);
    }
    progress(0.26);
    if (!await probe.canReachNetwork()) {
      assert(() {
        // ignore: avoid_print
        print('[HZ.GLEAM] first: DNS probe failed → offline');
        return true;
      }());
      return const OfflineTide(returnToNative: false);
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
      return PortalTide(reply.url!);
    }
    // Conversion had not arrived (the POST body had no af_status). Do not
    // lock the white route — the next cold start must run the pipeline again.
    // FORCE_PORTAL bypasses this because the override itself is the signal.
    if (!attribution.sawAttribution &&
        !GleamHorizonConfig.debugForcePortal) {
      assert(() {
        // ignore: avoid_print
        print('[HZ.GLEAM] first: no af_status yet, leaving route undecided');
        return true;
      }());
      return const NativeTide();
    }
    await vault.saveRoute(TideRoute.native);
    return const NativeTide();
  }

  Future<TideDestination> _returningPortal(
    void Function(double) progress,
  ) async {
    if (!await probe.hasInterface()) {
      return const OfflineTide(returnToNative: false);
    }
    final pending = await vault.consumePushUrl();
    if (pending != null && pending.isNotEmpty) {
      progress(1);
      return PortalTide(pending);
    }
    final cached = await vault.savedUrl();
    if (cached != null && !vault.cachedUrlExpired) {
      progress(1);
      return PortalTide(cached);
    }

    await Future.wait<void>(<Future<void>>[
      notifications.boot(),
      attribution.start(),
    ]);
    if (!await probe.canReachNetwork()) {
      return const OfflineTide(returnToNative: false);
    }
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
    await Future.wait<void>(<Future<void>>[
      notifications.boot(),
      attribution.start(),
    ]);
    if (!await probe.canReachNetwork()) {
      progress(1);
      return const NativeTide();
    }
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
