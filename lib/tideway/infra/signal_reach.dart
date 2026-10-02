import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

class SignalReach {
  final Connectivity _connectivity = Connectivity();

  Future<bool> hasInterface() async {
    try {
      final status = await _connectivity.checkConnectivity();
      return radiosUp(status);
    } catch (_) {
      return false;
    }
  }

  /// First-frame reachability. One TCP probe, no DNS cache. Used by the
  /// loading splash so a no-radio launch flips to nowifi within a frame.
  Future<bool> quickReach({
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    if (!await hasInterface()) return false;
    return _anyTcp(timeout);
  }

  /// Hard-capped TCP reachability. DNS lookup is not used: on a dead
  /// radio it can hang, and a cached answer looks like "online" so the
  /// splash would sit waiting for AppsFlyer until the user reconnects.
  Future<bool> canReachNetwork({
    Duration perHostTimeout = const Duration(milliseconds: 940),
    int attempts = 1,
    Duration retryDelay = const Duration(milliseconds: 380),
  }) async {
    if (!await hasInterface()) return false;
    final cap = perHostTimeout * attempts +
        retryDelay * (attempts > 0 ? attempts - 1 : 0) +
        const Duration(milliseconds: 220);
    try {
      return await _probe(perHostTimeout, attempts, retryDelay).timeout(
        cap,
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probe(
    Duration perHostTimeout,
    int attempts,
    Duration retryDelay,
  ) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (await _anyTcp(perHostTimeout)) return true;
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(retryDelay);
      }
    }
    return false;
  }

  Future<bool> _anyTcp(Duration timeout) async {
    final done = Completer<bool>();
    var left = 2;
    Future<void> one(String host) async {
      final reached = await _tcpOpen(host, 443, timeout);
      if (reached) {
        if (!done.isCompleted) done.complete(true);
        return;
      }
      left -= 1;
      if (left == 0 && !done.isCompleted) done.complete(false);
    }

    unawaited(one('1.1.1.1'));
    unawaited(one('8.8.8.8'));
    return done.future.timeout(timeout, onTimeout: () => false);
  }

  Future<bool> _tcpOpen(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool radiosUp(List<ConnectivityResult> status) => status.any(
        (value) =>
            value == ConnectivityResult.wifi ||
            value == ConnectivityResult.mobile ||
            value == ConnectivityResult.ethernet ||
            value == ConnectivityResult.vpn,
      );

  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;
}
