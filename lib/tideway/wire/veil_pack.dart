import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../config/gleam_horizon_config.dart';

/// Builds the opaque `{ schema, nonce, payload, tag }` envelope that the
/// slverhorizon.com relay expects on `POST /edge/sync`.
///
/// Wire format (field names and `schemaRev` are per-app and MUST match
/// the server's `relay_service.py` FIELD_* constants):
///
///   raw       = utf8( json(body, compact) )
///   nonce     = 16 random bytes
///   keystream = concat( sha256(secret + nonce + counterBE32) ) blocks
///   enc       = raw XOR keystream
///   tag       = HMAC_SHA256(secret, nonce + enc).hex()[:16]
///   envelope  = {
///     `schema`:  rev,
///     `nonce`:   nonce.hex(),
///     `payload`: base64Url(enc).rstrip('='),
///     `tag`:     tag,
///   }
///
/// The envelope is itself a JSON object: callers `jsonEncode(...)` the
/// returned map and POST that as the request body.
abstract final class VeilPack {
  /// Deterministic nonce hook used only in tests. Production code leaves
  /// this null and gets a cryptographic random nonce.
  static List<int> Function(int length)? debugNonceOverride;

  /// Packs [body] into the envelope and returns it as a `Map<String, dynamic>`
  /// ready for `jsonEncode`.
  static Map<String, dynamic> pack(Map<String, dynamic> body) {
    final secret = utf8.encode(GleamHorizonConfig.relaySecret);
    if (secret.isEmpty) {
      throw StateError('veil_pack: relay secret is not configured');
    }

    final raw = utf8.encode(jsonEncode(body));
    final nonce = _nonce(16);
    final enc = _xorKeystream(secret, nonce, raw);
    final tag = _tagHex(secret, nonce, enc);

    return <String, dynamic>{
      GleamHorizonConfig.envelopeFieldSchema:
          GleamHorizonConfig.envelopeSchemaRev,
      GleamHorizonConfig.envelopeFieldNonce: _hex(nonce),
      GleamHorizonConfig.envelopeFieldPayload: _base64UrlNoPad(enc),
      GleamHorizonConfig.envelopeFieldTag: tag,
    };
  }

  // ── internals ──────────────────────────────────────────────────────────

  static Uint8List _nonce(int length) {
    final override = debugNonceOverride;
    if (override != null) {
      final bytes = override(length);
      if (bytes.length != length) {
        throw StateError('veil_pack: debug nonce length mismatch');
      }
      return Uint8List.fromList(bytes);
    }
    final rng = math.Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  static Uint8List _xorKeystream(
    List<int> secret,
    Uint8List nonce,
    List<int> raw,
  ) {
    final out = Uint8List(raw.length);
    final seed = Uint8List(secret.length + nonce.length + 4)
      ..setRange(0, secret.length, secret)
      ..setRange(secret.length, secret.length + nonce.length, nonce);
    final counterOffset = secret.length + nonce.length;
    var produced = 0;
    var counter = 0;
    while (produced < raw.length) {
      // Big-endian 32-bit counter.
      seed[counterOffset] = (counter >> 24) & 0xff;
      seed[counterOffset + 1] = (counter >> 16) & 0xff;
      seed[counterOffset + 2] = (counter >> 8) & 0xff;
      seed[counterOffset + 3] = counter & 0xff;
      final block = sha256.convert(seed).bytes;
      final take = math.min(block.length, raw.length - produced);
      for (var i = 0; i < take; i++) {
        out[produced + i] = raw[produced + i] ^ block[i];
      }
      produced += take;
      counter++;
    }
    return out;
  }

  static String _tagHex(List<int> secret, Uint8List nonce, Uint8List enc) {
    final mac = Hmac(sha256, secret);
    final data = Uint8List(nonce.length + enc.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + enc.length, enc);
    final digest = mac.convert(data).bytes;
    return _hex(digest).substring(0, 16);
  }

  static String _hex(List<int> bytes) {
    const hex = '0123456789abcdef';
    final buf = StringBuffer();
    for (final b in bytes) {
      buf
        ..write(hex[(b >> 4) & 0xf])
        ..write(hex[b & 0xf]);
    }
    return buf.toString();
  }

  static String _base64UrlNoPad(List<int> bytes) {
    final encoded = base64Url.encode(bytes);
    final padStart = encoded.indexOf('=');
    return padStart < 0 ? encoded : encoded.substring(0, padStart);
  }
}
