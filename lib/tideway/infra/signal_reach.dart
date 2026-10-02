import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

class SignalReach {
  final Connectivity _connectivity = Connectivity();

  Future<bool> hasInterface() async {
    try {
      final status = await _connectivity.checkConnectivity();
      return status.any((value) => value != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<bool> canReachNetwork({
    Duration perHostTimeout = const Duration(seconds: 3),
    int attempts = 1,
    Duration retryDelay = const Duration(milliseconds: 450),
  }) async {
    if (!await hasInterface()) return false;
    // On a real cold start the Wi-Fi / cellular stack can report "connected"
    // before DNS is actually routable (first resolver request after wake can
    // take 1–2 s). A single short probe therefore misfires as "offline" with
    // the device sitting on strong signal, hence the retry loop below.
    for (var attempt = 0; attempt < attempts; attempt++) {
      for (final host in const <String>['google.com', 'icloud.com']) {
        try {
          final records = await InternetAddress.lookup(
            host,
          ).timeout(perHostTimeout);
          if (records.any((record) => record.rawAddress.isNotEmpty)) {
            return true;
          }
        } catch (_) {}
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(retryDelay);
      }
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;
}
