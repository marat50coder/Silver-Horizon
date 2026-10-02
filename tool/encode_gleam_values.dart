import 'dart:convert';

import 'package:horizongame/tideway/core/gleam_codec.dart';

const Map<String, String> _values = <String, String>{
  'endpoint': 'https://silverhorrizon.com/config.php',
  'appsFlyerKey': 'EsmEUBCyEMMMLQ3pGAzy2m',
  'firebaseProject': '21418836785',
  'gcd': 'https://gcdsdk.appsflyer.com/install_data/v5.0/',
  'oneLinkHost': 'silverhorizon.onelink.me',
  'webkit': '605.1.15',
  'safari': '18.4',
  'safariTail': '604.1',
  'uaProduct': 'Mozilla/5.0',
  'uaPlatA': ' (iPhone; CPU iPhone OS ',
  'uaPlatB': ' like Mac OS X) ',
  'uaEngine': 'AppleWebKit/',
  'uaGecko': ' (KHTML, like Gecko) ',
  'uaVer': 'Version/',
  'uaMobile': ' Mobile/15E148 ',
  'uaSafari': 'Safari/',
};

void main() {
  for (final entry in _values.entries) {
    final wrapped = foldGleam(entry.value);
    final bytes = base64Decode(wrapped);
    final back = unfoldGleam(bytes);
    if (back != entry.value) {
      throw StateError('VERIFY failed for ${entry.key}: $back');
    }
    // ignore: avoid_print
    print('${entry.key} (${bytes.length}): ${bytes.toList()}');
    // ignore: avoid_print
    print('  b64=$wrapped');
  }
  // ignore: avoid_print
  print('VERIFY OK');
}
