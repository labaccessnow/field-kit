/// JWT decoding (no verification — decode-only, and the UI says so).
library;
import 'dart:convert';

List<int> b64urlBytes(String s) {
  var t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64.decode(t);
}

class JwtResult {
  final Map<String, dynamic>? header;
  final Map<String, dynamic>? payload;
  final String? sig;
  final List<String> warnings;
  final String? err;
  JwtResult(this.header, this.payload, this.sig, this.warnings) : err = null;
  JwtResult.fail(this.err)
      : header = null,
        payload = null,
        sig = null,
        warnings = const [];
}

JwtResult jwtDecode(String tok) {
  final t = tok.trim().replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
  final parts = t.split('.');
  if (parts.length != 3) {
    return JwtResult.fail(
        'A JWT has three dot-separated parts — got ${parts.length}.');
  }
  Map<String, dynamic> header, payload;
  try {
    header = jsonDecode(utf8.decode(b64urlBytes(parts[0]), allowMalformed: true))
        as Map<String, dynamic>;
  } catch (_) {
    return JwtResult.fail('Header is not valid Base64URL JSON.');
  }
  try {
    payload = jsonDecode(utf8.decode(b64urlBytes(parts[1]), allowMalformed: true))
        as Map<String, dynamic>;
  } catch (_) {
    return JwtResult.fail('Payload is not valid Base64URL JSON.');
  }
  final warnings = <String>[];
  final alg = (header['alg'] ?? '').toString().toLowerCase();
  if (alg == 'none') {
    warnings.add('alg is "none" — this token is UNSIGNED. Nothing should accept it.');
  }
  if (header['alg'] == null) warnings.add('No alg in header.');
  return JwtResult(header, payload, parts[2], warnings);
}
