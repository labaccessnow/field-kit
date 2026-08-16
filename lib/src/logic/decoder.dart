/// Decoder workbench operations. Every op returns (out, err) so the UI can
/// chain them without try/catch noise.
library;
import 'dart:convert';

typedef OpResult = ({String? out, String? err});

OpResult _ok(String s) => (out: s, err: null);
OpResult _fail(String e) => (out: null, err: e);

OpResult b64decode(String s) {
  try {
    var t = s.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '+').replaceAll('_', '/');
    if (t.isEmpty) return _fail('Nothing to decode.');
    while (t.length % 4 != 0) {
      t += '=';
    }
    return _ok(utf8.decode(base64.decode(t), allowMalformed: true));
  } catch (_) {
    return _fail('Not valid Base64.');
  }
}

OpResult b64encode(String s) => _ok(base64.encode(utf8.encode(s)));

OpResult hexToText(String s) {
  final t = s.replaceAll(RegExp(r'0x', caseSensitive: false), '')
      .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (t.isEmpty) return _fail('No hex digits found.');
  if (t.length.isOdd) return _fail('Odd number of hex digits.');
  final bytes = <int>[];
  for (var i = 0; i < t.length; i += 2) {
    bytes.add(int.parse(t.substring(i, i + 2), radix: 16));
  }
  return _ok(utf8.decode(bytes, allowMalformed: true));
}

OpResult textToHex(String s) =>
    _ok(utf8.encode(s).map((b) => b.toRadixString(16).padLeft(2, '0')).join());

OpResult urlDecode(String s) {
  try {
    return _ok(Uri.decodeComponent(s.replaceAll('+', '%20')));
  } catch (_) {
    return _fail('Bad percent-encoding.');
  }
}

OpResult urlEncode(String s) => _ok(Uri.encodeComponent(s));

OpResult rot13(String s) => _ok(String.fromCharCodes(s.codeUnits.map((c) {
      if (c >= 65 && c <= 90) return (c - 65 + 13) % 26 + 65;
      if (c >= 97 && c <= 122) return (c - 97 + 13) % 26 + 97;
      return c;
    })));

const _entities = <String, String>{
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'copy': '©', 'reg': '®', 'trade': '™', 'hellip': '…',
  'mdash': '—', 'ndash': '–', 'lsquo': '‘', 'rsquo': '’',
  'ldquo': '“', 'rdquo': '”',
};

OpResult htmlDecode(String s) {
  final out = s.replaceAllMapped(
      RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
    final e = m[1]!;
    if (e.startsWith('#x') || e.startsWith('#X')) {
      final cp = int.tryParse(e.substring(2), radix: 16);
      return cp != null ? String.fromCharCode(cp) : m[0]!;
    }
    if (e.startsWith('#')) {
      final cp = int.tryParse(e.substring(1));
      return cp != null ? String.fromCharCode(cp) : m[0]!;
    }
    return _entities[e.toLowerCase()] ?? m[0]!;
  });
  return _ok(out);
}
