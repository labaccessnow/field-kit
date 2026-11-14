// Ping and traceroute for phones.
//
// Android: there is no traceroute command, but the system ping can set the
// TTL (-t). The router where the TTL runs out answers "Time to live exceeded"
// from its own address, so probing TTL 1, 2, 3... walks the path hop by hop.
//
// iPhone: apps cannot send ICMP at all, so "ping" times a TCP connect instead
// (the handshake is one round trip). Traceroute is not offered there.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'netdial.dart';

/// One TTL-limited ping, parsed.
class TtlProbe {
  /// Address that answered; null = no answer within the timeout.
  final String? hop;

  /// Round trip in ms. Only the destination's echo reply carries a time.
  final double? ms;

  /// True when the destination itself answered (the trace is done).
  final bool reached;

  /// A router answered "Destination ... Unreachable": no route past it.
  final bool unreachable;

  const TtlProbe(this.hop, this.ms, this.reached, {this.unreachable = false});
}

final _reply = RegExp(r'bytes from (\S+?):?\s.*?time[=<]([0-9.]+)\s*ms');
final _exceeded = RegExp(
    r'From (\S+?):?\s+icmp_seq=\d+\s+Time to live exceeded',
    caseSensitive: false);
final _unreach = RegExp(
    r'From (\S+?):?\s+icmp_seq=\d+\s+Destination \w*\s*Unreachable',
    caseSensitive: false);

/// Parses the output of `ping -n -c 1 -t <ttl> <ip>` (iputils, as on Android).
TtlProbe parseTtlProbe(String pingOutput) {
  final r = _reply.firstMatch(pingOutput);
  if (r != null) return TtlProbe(r[1], double.tryParse(r[2]!), true);
  final x = _exceeded.firstMatch(pingOutput);
  if (x != null) return TtlProbe(x[1], null, false);
  final u = _unreach.firstMatch(pingOutput);
  if (u != null) return TtlProbe(u[1], null, false, unreachable: true);
  return const TtlProbe(null, null, false);
}

/// One traceroute-style line for a hop.
String hopLine(int ttl, TtlProbe p) {
  final n = ttl.toString().padLeft(2);
  if (p.hop == null) return '$n  *';
  if (p.unreachable) return '$n  ${p.hop}  !H (destination unreachable)';
  if (p.ms != null) return '$n  ${p.hop}  ${p.ms!.toStringAsFixed(1)} ms';
  return '$n  ${p.hop}';
}

/// Prefers an IPv4 address (what most people expect to see traced).
Future<InternetAddress> resolvePreferV4(String host) async =>
    (await _addresses(host)).first;

/// Every address of [host], IPv4 ones first.
Future<List<InternetAddress>> _addresses(String host, {Lookup? lookup}) async {
  final addrs = await (lookup ?? InternetAddress.lookup)(host);
  return [
    ...addrs.where((a) => a.type == InternetAddressType.IPv4),
    ...addrs.where((a) => a.type != InternetAddressType.IPv4),
  ];
}

/// Android traceroute: one ping per TTL, streamed a line at a time.
/// [runPing] is injectable for tests.
Stream<String> pingTrace(
  String host, {
  int maxHops = 30,
  Future<ProcessResult> Function(String exe, List<String> args)? runPing,
}) async* {
  final run = runPing ?? (exe, args) => Process.run(exe, args);
  final addr = await resolvePreferV4(host);
  final exe = addr.type == InternetAddressType.IPv6 ? 'ping6' : 'ping';
  yield 'traceroute to $host (${addr.address}), $maxHops hops max\n'
      'Hop times are not measured this way; the last line shows the round trip.\n\n';
  for (var ttl = 1; ttl <= maxHops; ttl++) {
    final r = await run(exe, ['-n', '-c', '1', '-W', '1', '-t', '$ttl', addr.address]);
    final p = parseTtlProbe('${r.stdout}\n${r.stderr}');
    yield '${hopLine(ttl, p)}\n';
    if (p.reached || p.unreachable) return;
  }
}

/// iPhone "ping": [count] TCP connects to [port], timed.
/// A refused connection still counts: the host answered (port closed).
///
/// On an IPv6-only network an IPv4 address has no route. The first attempt
/// then moves to the host's IPv6 address, or to the NAT64 form of the IPv4
/// one, and the remaining attempts stay there.
Future<String> tcpPing(String host,
    {int port = 443,
    int count = 4,
    Duration gap = const Duration(milliseconds: 500),
    Duration timeout = const Duration(seconds: 3),
    Lookup? lookup,
    Connect? connect}) async {
  final open = connect ?? systemConnect;
  final addrs = await _addresses(host, lookup: lookup);
  var addr = addrs.first;
  InternetAddress? nat64Of;
  final lines = <String>[];
  final times = <double>[];

  // One timed connect. Returns the error when the address had no route.
  Future<SocketException?> attempt(int i) async {
    final sw = Stopwatch()..start();
    try {
      final s = await open(addr, port, timeout: timeout);
      sw.stop();
      s.destroy();
      times.add(sw.elapsedMicroseconds / 1000);
      lines.add('seq=$i  time=${times.last.toStringAsFixed(1)} ms');
    } on SocketException catch (e) {
      sw.stop();
      if (noRoute(e)) return e;
      final msg = e.osError?.message ?? e.message;
      if (msg.toLowerCase().contains('refused')) {
        times.add(sw.elapsedMicroseconds / 1000);
        lines.add(
            'seq=$i  time=${times.last.toStringAsFixed(1)} ms  (refused: host answered, port $port closed)');
      } else {
        lines.add('seq=$i  no answer ($msg)');
      }
    }
    return null;
  }

  for (var i = 1; i <= count; i++) {
    var unroutable = await attempt(i);
    if (unroutable != null && i == 1 && addr.type == InternetAddressType.IPv4) {
      final v6 = addrs.where((a) => a.type == InternetAddressType.IPv6);
      final other =
          v6.isNotEmpty ? v6.first : await nat64For(addr, lookup: lookup);
      if (other != null) {
        if (v6.isEmpty) nat64Of = addr;
        addr = other;
        unroutable = await attempt(i);
      }
    }
    if (unroutable != null) {
      lines.add(
          'seq=$i  no answer (${unroutable.osError?.message ?? unroutable.message})');
    }
    if (i < count) await Future<void>.delayed(gap);
  }

  final out = StringBuffer('TCP connect to $host (${addr.address}) port $port\n');
  if (nat64Of != null) {
    out.writeln(
        'IPv6-only network: reaching ${nat64Of.address} through its NAT64 address.');
  }
  lines.forEach(out.writeln);
  out.write('\n${times.length}/$count answered');
  if (times.isNotEmpty) {
    final avg = times.reduce((a, b) => a + b) / times.length;
    out.write(', min/avg/max = ${times.reduce(math.min).toStringAsFixed(1)}/'
        '${avg.toStringAsFixed(1)}/${times.reduce(math.max).toStringAsFixed(1)} ms');
  }
  return out.toString();
}
