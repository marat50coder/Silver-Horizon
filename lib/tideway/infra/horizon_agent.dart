import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../config/gleam_horizon_config.dart';

class HorizonAgent extends http.BaseClient {
  final http.Client _transport = http.Client();
  String? _userAgent;

  Future<void> prepare() async {
    try {
      if (!Platform.isIOS) {
        _userAgent = _fallback();
        return;
      }
      final info = await DeviceInfoPlugin().iosInfo;
      final version = _normalizedIos(info.systemVersion);
      _userAgent = _mobileSafari(version);
    } catch (_) {
      _userAgent = _fallback();
    }
  }

  String get userAgent => _userAgent ?? _fallback();

  String _normalizedIos(String raw) {
    final components = raw
        .split('.')
        .map((part) => int.tryParse(part))
        .whereType<int>()
        .take(3)
        .toList();
    if (components.isEmpty || components.first < 18) {
      return GleamHorizonConfig.safariVersion;
    }
    return components.join('.');
  }

  // GAME THEME CATEGORY: crash (partner identity suffix omitted)
  String _mobileSafari(String iosVersion) {
    final cpu = iosVersion.replaceAll('.', '_');
    return GleamHorizonConfig.uaProduct +
        GleamHorizonConfig.uaPlatformPrefix +
        cpu +
        GleamHorizonConfig.uaPlatformSuffix +
        GleamHorizonConfig.uaEngine +
        GleamHorizonConfig.webKitVersion +
        GleamHorizonConfig.uaGecko +
        GleamHorizonConfig.uaVersionToken +
        GleamHorizonConfig.safariVersion +
        GleamHorizonConfig.uaMobileToken +
        GleamHorizonConfig.uaSafariToken +
        GleamHorizonConfig.safariTail;
  }

  String _fallback() => _mobileSafari(GleamHorizonConfig.safariVersion);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _transport.send(request);
  }

  @override
  void close() => _transport.close();
}
