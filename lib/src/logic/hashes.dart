/// Hash identification. Digesting itself is package:crypto, wired in the UI.
library;

String identifyHash(String h) {
  final t = h.trim();
  if (t.isEmpty) return '';
  bool hex(int n) => RegExp('^[0-9a-f]{$n}\$', caseSensitive: false).hasMatch(t);
  if (t.startsWith(RegExp(r'\$2[aby]\$'))) return 'bcrypt';
  if (RegExp(r'^\$argon2', caseSensitive: false).hasMatch(t)) return 'Argon2';
  if (t.startsWith(r'$6$')) return 'SHA-512 crypt (Unix shadow)';
  if (t.startsWith(r'$5$')) return 'SHA-256 crypt (Unix shadow)';
  if (t.startsWith(r'$1$')) return 'MD5 crypt (Unix shadow)';
  if (t.startsWith(r'$y$')) return 'yescrypt (Unix shadow)';
  if (RegExp(r'^[0-9a-f]{32}:[0-9a-f]{32}$', caseSensitive: false).hasMatch(t)) {
    return 'LM:NT hash pair (secretsdump style)';
  }
  if (hex(32)) return '32 hex — MD5 (file/IOC) or NTLM (credential)';
  if (hex(40)) return '40 hex — SHA-1';
  if (hex(56)) return '56 hex — SHA-224';
  if (hex(64)) return '64 hex — SHA-256';
  if (hex(96)) return '96 hex — SHA-384';
  if (hex(128)) return '128 hex — SHA-512';
  if (RegExp(r'^[A-Za-z0-9+/_-]{16,}={0,2}$').hasMatch(t)) {
    return 'Looks Base64-encoded — decode it first';
  }
  return 'Not a common hash format';
}
