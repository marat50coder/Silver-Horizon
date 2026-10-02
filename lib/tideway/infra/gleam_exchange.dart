import 'dart:convert';

import '../config/gleam_horizon_config.dart';
import '../core/gleam_models.dart';
import '../wire/veil_pack.dart';
import 'gleam_attribution.dart';
import 'horizon_agent.dart';
import 'horizon_vault.dart';

class GleamExchange {
  GleamExchange(this._agent, this._vault);

  final HorizonAgent _agent;
  final HorizonVault _vault;

  Future<GleamReply> request(Map<String, dynamic> payload) async {
    if (!GleamHorizonConfig.grayCredentialsReady) {
      return GleamReply.rejected('credentials_unavailable');
    }
    try {
      gleamTrace(() => '[HZ.EXCHANGE] request ${jsonEncode(payload)}');
      // Wrap the clean attribution JSON in the opaque /edge/sync envelope.
      // The relay unpacks it (schema=h, nonce=x, payload=u, tag=j, rev=13)
      // and forwards the inner JSON to the partner config.php verbatim.
      // Never POST plaintext bodies to the endpoint — nginx will return the
      // 404 decoy for anything missing a valid HMAC tag.
      final Map<String, dynamic> envelope = VeilPack.pack(payload);
      final response = await _agent
          .post(
            Uri.parse(GleamHorizonConfig.endpoint),
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(envelope),
          )
          .timeout(
            const Duration(
              seconds: GleamHorizonConfig.exchangeTimeoutSeconds,
            ),
          );
      gleamTrace(
        () =>
            '[HZ.EXCHANGE] response ${response.statusCode} ${response.body}',
      );
      if (response.statusCode != 200) {
        return GleamReply.rejected('http_${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return GleamReply.rejected('invalid_response');
      final reply = GleamReply.fromJson(Map<String, dynamic>.from(decoded));
      if (reply.hasDestination) {
        await _vault.cacheUrl(reply.url!, reply.expiresAt);
      }
      return reply;
    } catch (error) {
      gleamTrace(() => '[HZ.EXCHANGE] failed: $error');
      return GleamReply.rejected('network_failure');
    }
  }
}
