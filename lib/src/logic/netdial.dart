// Opening TCP connections on any kind of network.
//
// Names go through the system resolver, and on an IPv6-only network (many
// phone carriers run one) the resolver hands back addresses that the
// network's NAT64 gateway can reach. A typed IPv4 address has no name to
// resolve, so the app does the resolver's job itself: it asks for the
// well-known name ipv4only.arpa (RFC 7050), reads the network's NAT64 prefix
// out of the answer, and embeds the IPv4 address in it (RFC 6052).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

typedef Lookup = Future<List<InternetAddress>> Function(String host,
    {InternetAddressType type});
typedef Connect = Future<Socket> Function(Object target, int port,
    {Duration? timeout});

/// The plain system connect: [target] is a host name or an [InternetAddress].
Future<Socket> systemConnect(Object target, int port, {Duration? timeout}) =>
    Socket.connect(target, port, timeout: timeout);

/// The two IPv4 addresses ipv4only.arpa always has (RFC 7050).
const _wellKnown = [
  [192, 0, 0, 170],
  [192, 0, 0, 171],
];

/// Prefix lengths a NAT64 prefix may have (RFC 6052), most common first.
const _prefixBits = [96, 64, 56, 48, 40, 32];

/// Embeds the four bytes of [v4] after the first [bits] bits of [prefix],
/// as RFC 6052 section 2.2 lays it out. Byte 8 is reserved and stays zero.
Uint8List embedV4(List<int> prefix, int bits, List<int> v4) {
  final out = Uint8List(16);
  var pos = bits ~/ 8;
  out.setRange(0, pos, prefix);
  for (final b in v4) {
    if (pos == 8) pos++;
    out[pos++] = b;
  }
  return out;
}

/// A NAT64 prefix: 16 bytes, of which the first [bits] bits count.
class Nat64Prefix {
  final Uint8List bytes;
  final int bits;
  const Nat64Prefix(this.bytes, this.bits);

  InternetAddress embed(InternetAddress v4) =>
      InternetAddress.fromRawAddress(embedV4(bytes, bits, v4.rawAddress));
}

/// Finds the NAT64 prefix in the IPv6 answers for ipv4only.arpa: the answer
/// that has a well-known address embedded at one of the six legal positions.
/// Null when no answer does (the network has no NAT64).
Nat64Prefix? nat64Prefix(List<InternetAddress> answers) {
  for (final a in answers) {
    if (a.type != InternetAddressType.IPv6) continue;
    final raw = a.rawAddress;
    for (final bits in _prefixBits) {
      for (final wk in _wellKnown) {
        final rebuilt = embedV4(raw, bits, wk);
        var same = true;
        for (var i = 0; i < 16 && same; i++) {
          same = rebuilt[i] == raw[i];
        }
        if (same) return Nat64Prefix(Uint8List.fromList(raw), bits);
      }
    }
  }
  return null;
}

/// True when [e] means "no route from here to that kind of address": what a
/// connect to an IPv4 address gets on an IPv6-only network.
bool noRoute(SocketException e) {
  final code = e.osError?.errorCode;
  // ENETUNREACH and EHOSTUNREACH, as each system numbers them.
  final codes = Platform.isIOS || Platform.isMacOS
      ? const [51, 65]
      : Platform.isWindows
          ? const [10051, 10065]
          : const [101, 113];
  if (code != null && codes.contains(code)) return true;
  final msg = '${e.osError?.message ?? ''} ${e.message}'.toLowerCase();
  return msg.contains('unreachable') || msg.contains('no route');
}

/// The address that reaches [v4] through this network's NAT64, or null when
/// the network has none.
Future<InternetAddress?> nat64For(InternetAddress v4, {Lookup? lookup}) async {
  try {
    final answers = await (lookup ?? InternetAddress.lookup)('ipv4only.arpa',
            type: InternetAddressType.IPv6)
        .timeout(const Duration(seconds: 4));
    return nat64Prefix(answers)?.embed(v4);
  } on SocketException {
    return null;
  } on TimeoutException {
    return null;
  }
}

/// Opens a TCP connection to [host]:[port]. A name is resolved by the system
/// and every address it has is tried. An IPv4 address that has no route (an
/// IPv6-only network) is retried through the network's NAT64.
Future<Socket> dial(String host, int port,
    {Duration? timeout, Lookup? lookup, Connect? connect}) async {
  final open = connect ?? systemConnect;
  try {
    return await open(host, port, timeout: timeout);
  } on SocketException catch (e) {
    final v4 = InternetAddress.tryParse(host);
    if (v4 == null || v4.type != InternetAddressType.IPv4 || !noRoute(e)) {
      rethrow;
    }
    final via = await nat64For(v4, lookup: lookup);
    if (via == null) rethrow;
    return open(via, port, timeout: timeout);
  }
}

/// [dial], then TLS. The certificate is checked against [host] as it was
/// typed, also when the connection itself went through NAT64. [anyCert]
/// skips the check, to read a certificate the system does not trust.
Future<SecureSocket> dialTls(String host, int port,
    {bool anyCert = false, Duration? timeout}) async {
  final raw = await dial(host, port, timeout: timeout);
  return SecureSocket.secure(raw,
      host: host, onBadCertificate: anyCert ? (_) => true : null);
}
