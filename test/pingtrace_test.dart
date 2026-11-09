import 'dart:io';

import 'package:fieldkit/src/logic/pingtrace.dart';
import 'package:flutter_test/flutter_test.dart';

// iputils output (the ping Android ships), both "From" spellings. Addresses
// are 0.0.0.x placeholders: this repo is public and carries no real IPs.
const _exceededOld = '''PING 0.0.0.9 (0.0.0.9) 56(84) bytes of data.
From 0.0.0.1: icmp_seq=1 Time to live exceeded

--- 0.0.0.9 ping statistics ---
1 packets transmitted, 0 received, +1 errors, 100% packet loss, time 0ms
''';
const _exceededNew = 'From 0.0.0.2 icmp_seq=1 Time to live exceeded\n';
const _exceededV6 = 'From 2001:db8::1 icmp_seq=1 Time to live exceeded\n';
const _reply = '''PING 0.0.0.9 (0.0.0.9) 56(84) bytes of data.
64 bytes from 0.0.0.9: icmp_seq=1 ttl=57 time=12.3 ms

--- 0.0.0.9 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
''';
const _silent = '''PING 0.0.0.9 (0.0.0.9) 56(84) bytes of data.

--- 0.0.0.9 ping statistics ---
1 packets transmitted, 0 received, 100% packet loss, time 0ms
''';

void main() {
  group('parseTtlProbe', () {
    test('TTL exceeded, both iputils spellings and IPv6', () {
      expect(parseTtlProbe(_exceededOld).hop, '0.0.0.1');
      expect(parseTtlProbe(_exceededNew).hop, '0.0.0.2');
      expect(parseTtlProbe(_exceededV6).hop, '2001:db8::1');
      expect(parseTtlProbe(_exceededOld).reached, isFalse);
    });
    test('destination reply carries the round trip', () {
      final p = parseTtlProbe(_reply);
      expect(p.hop, '0.0.0.9');
      expect(p.ms, 12.3);
      expect(p.reached, isTrue);
    });
    test('an unreachable answer ends the trace with !H', () {
      // What the Android emulator's virtual router sends back for TTL probes.
      final p = parseTtlProbe(
          'From 0.0.0.3: icmp_seq=1 Destination Host Unreachable\n');
      expect(p.unreachable, isTrue);
      expect(hopLine(1, p), ' 1  0.0.0.3  !H (destination unreachable)');
    });
    test('no answer is a star', () {
      final p = parseTtlProbe(_silent);
      expect(p.hop, isNull);
      expect(hopLine(4, p), ' 4  *');
    });
  });

  test('pingTrace walks TTLs and stops at the destination', () async {
    final asked = <String>[];
    Future<ProcessResult> fake(String exe, List<String> args) async {
      asked.add('$exe ${args.join(' ')}');
      final ttl = int.parse(args[args.indexOf('-t') + 1]);
      final out = switch (ttl) {
        1 => _exceededOld,
        2 => _silent,
        _ => _reply,
      };
      return ProcessResult(0, 0, out, '');
    }

    final lines = await pingTrace('0.0.0.9', runPing: fake).toList();
    final hops = lines.skip(1).map((l) => l.trim()).toList();
    expect(hops, ['1  0.0.0.1', '2  *', '3  0.0.0.9  12.3 ms']);
    expect(asked.first, 'ping -n -c 1 -W 1 -t 1 0.0.0.9');
    expect(asked.length, 3);
  });

  test('tcpPing times connects to a live listener', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => s.destroy());
    addTearDown(server.close);
    final out = await tcpPing('127.0.0.1',
        port: server.port, count: 3, gap: Duration.zero);
    expect(out, contains('3/3 answered'));
    expect(out, contains('min/avg/max'));
  });

  test('tcpPing counts a refused port as an answer', () async {
    // Bind then close to get a port that is surely not listening.
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    final out =
        await tcpPing('127.0.0.1', port: port, count: 2, gap: Duration.zero);
    expect(out, contains('refused'));
    expect(out, contains('2/2 answered'));
  });
}
