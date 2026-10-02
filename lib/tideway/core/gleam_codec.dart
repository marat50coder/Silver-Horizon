import 'dart:convert';
import 'dart:typed_data';

/// Per-app XOR salt. Do not reuse across products.
const List<int> _horizonSalt = <int>[
  0x53,
  0x48,
  0x2E,
  0x37,
  0x41,
  0x2D,
  0x6C,
  0x39,
  0x39,
  0x36,
  0x4B,
  0x37,
];

int _mix(int index) =>
    _horizonSalt[index % _horizonSalt.length] ^ ((index * 31 + 19) & 0xff);

/// XOR-fold UTF-8, then wrap as base64. Inverse of [unfoldGleam].
String foldGleam(String plain) {
  final bytes = utf8.encode(plain);
  final mixed = Uint8List(bytes.length);
  for (var index = 0; index < bytes.length; index++) {
    mixed[index] = bytes[index] ^ _mix(index);
  }
  return base64Encode(mixed);
}

/// Decode a base64 XOR payload produced by [foldGleam] or stored as bytes.
String unfoldGleam(List<int> encoded) {
  if (encoded.isEmpty) return '';
  final plain = Uint8List(encoded.length);
  for (var index = 0; index < encoded.length; index++) {
    plain[index] = encoded[index] ^ _mix(index);
  }
  return utf8.decode(plain);
}
