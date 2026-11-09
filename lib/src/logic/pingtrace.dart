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
Future<InternetAddress> resolvePreferV4(String host) async {
  final addrs = await InternetAddress.lookup(host);
  return addrs.firstWhere((a) => a.type == InternetAddressType.IPv4,
      orElse: () => addrs.first);
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
Future<String> tcpPing(String host,
    {int port = 443,
    int count = 4,
    Duration gap = const Duration(milliseconds: 500),
    Duration timeout = const Duration(seconds: 3)}) async {
  final addr = await resolvePreferV4(host);
  final out = StringBuffer('TCP connect to $host (${addr.address}) port $port\n');
  final times = <double>[];
  for (var i = 1; i <= count; i++) {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(addr, port, timeout: timeout);
      sw.stop();
      s.destroy();
      times.add(sw.elapsedMicroseconds / 1000);
      out.writeln('seq=$i  time=${times.last.toStringAsFixed(1)} ms');
    } on SocketException catch (e) {
      sw.stop();
      final msg = e.osError?.message ?? e.message;
      if (msg.toLowerCase().contains('refused')) {
        times.add(sw.elapsedMicroseconds / 1000);
        out.writeln(
            'seq=$i  time=${times.last.toStringAsFixed(1)} ms  (refused: host answered, port $port closed)');
      } else {
        out.writeln('seq=$i  no answer ($msg)');
      }
    }
    if (i < count) await Future<void>.delayed(gap);
  }
  out.write('\n${times.length}/$count answered');
  if (times.isNotEmpty) {
    final avg = times.reduce((a, b) => a + b) / times.length;
    out.write(', min/avg/max = ${times.reduce(math.min).toStringAsFixed(1)}/'
        '${avg.toStringAsFixed(1)}/${times.reduce(math.max).toStringAsFixed(1)} ms');
  }
  return out.toString();
}
