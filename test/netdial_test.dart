import 'dart:io';
import 'dart:typed_data';

import 'package:fieldkit/src/logic/netdial.dart';
import 'package:fieldkit/src/logic/pingtrace.dart';
import 'package:flutter_test/flutter_test.dart';

// IPv4 addresses here are byte lists or 0.0.0.x placeholders: this repo is
// public and carries no real IPs. IPv6 ones are the documentation prefix and
// the well-known NAT64 prefix.

String v6(List<int> bytes) => InternetAddress.fromRawAddress(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes))
    .address;
/// [a] spelled the way the system prints an address built from bytes.
String norm(String a) =>
    InternetAddress.fromRawAddress(InternetAddress(a).rawAddress).address;
List<int> raw(String a) => InternetAddress(a).rawAddress;

/// What a connect gets when the network has no route for that address family.
SocketException unreachable() => const SocketException('Connection failed',
    osError: OSError('Network is unreachable', 101));

/// The answer an IPv6-only network's resolver gives for ipv4only.arpa.
final arpaAnswers = [
  InternetAddress('64:ff9b::c000:aa'),
  InternetAddress('64:ff9b::c000:ab'),
];

void main() {
  group('embedV4 (RFC 6052 section 2.4 examples)', () {
    const v4 = [192, 0, 2, 33];
    const cases = {
      32: ('2001:db8::', '2001:db8:c000:221::'),
      40: ('2001:db8:100::', '2001:db8:1c0:2:21::'),
      48: ('2001:db8:122::', '2001:db8:122:c000:2:2100::'),
      56: ('2001:db8:122:300::', '2001:db8:122:3c0:0:221::'),
      64: ('2001:db8:122:344::', '2001:db8:122:344:c0:2:2100::'),
      96: ('2001:db8:122:344::', '2001:db8:122:344::c000:221'),
    };
    for (final c in cases.entries) {
      test('/${c.key}', () {
        expect(v6(embedV4(raw(c.value.$1), c.key, v4)), norm(c.value.$2));
      });
    }
  });

  group('nat64Prefix', () {
    test('the well-known prefix', () {
      final p = nat64Prefix(arpaAnswers)!;
      expect(p.bits, 96);
      expect(p.embed(InternetAddress('0.0.0.9')).address, norm('64:ff9b::9'));
    });

    test('a network-specific /64 prefix', () {
      final p = nat64Prefix([InternetAddress('2001:db8:122:344:c0:0:aa00:0')])!;
      expect(p.bits, 64);
      expect(v6(embedV4(p.bytes, p.bits, [192, 0, 2, 33])),
          norm('2001:db8:122:344:c0:2:2100::'));
    });

    test('no NAT64: an ordinary address, an IPv4 answer, or nothing', () {
      expect(nat64Prefix([InternetAddress('2001:db8::1')]), isNull);
      expect(nat64Prefix([InternetAddress('0.0.0.9')]), isNull);
      expect(nat64Prefix([]), isNull);
    });
  });

  test('noRoute: unreachable yes, refused no', () {
    expect(noRoute(unreachable()), isTrue);
    expect(
        noRoute(const SocketException('x',
            osError: OSError('No route to host', 113))),
        isTrue);
    expect(
        noRoute(const SocketException('x',
            osError: OSError('Connection refused', 111))),
        isFalse);
  });

  group('with a listener standing in for the far end', () {
    late ServerSocket server;
    late List<Object> dialled;
    late List<String> lookedUp;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((s) => s.destroy());
      dialled = [];
      lookedUp = [];
    });
    tearDown(() => server.close());

    // An IPv6-only network: IPv4 targets have no route, IPv6 ones connect.
    Future<Socket> v6Only(Object target, int port, {Duration? timeout}) {
      dialled.add(target is InternetAddress ? target.address : target);
      final isV4 = target is InternetAddress
          ? target.type == InternetAddressType.IPv4
          : InternetAddress.tryParse(target as String)?.type ==
              InternetAddressType.IPv4;
      if (isV4) throw unreachable();
      return Socket.connect(InternetAddress.loopbackIPv4, server.port);
    }

    // An ordinary network: everything connects.
    Future<Socket> anyNet(Object target, int port, {Duration? timeout}) {
      dialled.add(target is InternetAddress ? target.address : target);
      return Socket.connect(InternetAddress.loopbackIPv4, server.port);
    }

    // A resolver with DNS64: names in [names], plus ipv4only.arpa.
    Lookup resolver(Map<String, List<String>> names, {bool nat64 = true}) =>
        (String host, {InternetAddressType type = InternetAddressType.any}) async {
          lookedUp.add(host);
          if (host == 'ipv4only.arpa') {
            if (!nat64) throw const SocketException('Failed host lookup');
            return arpaAnswers;
          }
          final literal = InternetAddress.tryParse(host);
          if (literal != null) return [literal];
          return [for (final a in names[host] ?? <String>[]) InternetAddress(a)];
        };

    test('dial: an IPv4 address goes through NAT64 on an IPv6-only network',
        () async {
      final s = await dial('0.0.0.9', 443,
          connect: v6Only, lookup: resolver({}));
      s.destroy();
      expect(dialled, ['0.0.0.9', norm('64:ff9b::9')]);
    });

    test('dial: an ordinary network never asks about NAT64', () async {
      final s = await dial('0.0.0.9', 443,
          connect: anyNet, lookup: resolver({}));
      s.destroy();
      expect(dialled, ['0.0.0.9']);
      expect(lookedUp, isEmpty);
    });

    test('dial: no NAT64 on the network keeps the original error', () async {
      await expectLater(
          dial('0.0.0.9', 443,
              connect: v6Only, lookup: resolver({}, nat64: false)),
          throwsA(isA<SocketException>().having(
              (e) => e.osError?.message, 'message', 'Network is unreachable')));
    });

    test('dial: a name is left to the system resolver', () async {
      Future<Socket> fails(Object t, int p, {Duration? timeout}) {
        dialled.add(t);
        throw unreachable();
      }

      await expectLater(
          dial('host.example', 443, connect: fails, lookup: resolver({})),
          throwsA(isA<SocketException>()));
      expect(dialled, ['host.example']);
      expect(lookedUp, isEmpty);
    });

    test('tcpPing: an IPv4 address on an IPv6-only network', () async {
      final out = await tcpPing('0.0.0.9',
          count: 2,
          gap: Duration.zero,
          connect: v6Only,
          lookup: resolver({}));
      expect(out, contains('TCP connect to 0.0.0.9 (${norm('64:ff9b::9')})'));
      expect(out,
          contains('IPv6-only network: reaching 0.0.0.9 through its NAT64'));
      expect(out, contains('2/2 answered'));
      // One failed IPv4 try, then both pings on the NAT64 address.
      expect(dialled, ['0.0.0.9', norm('64:ff9b::9'), norm('64:ff9b::9')]);
    });

    test('tcpPing: a name with both address kinds moves to its IPv6 one',
        () async {
      final out = await tcpPing('host.example',
          count: 2,
          gap: Duration.zero,
          connect: v6Only,
          lookup: resolver({
            'host.example': ['2001:db8::5', '0.0.0.9']
          }));
      expect(out, contains('TCP connect to host.example (2001:db8::5)'));
      expect(out, isNot(contains('NAT64')));
      expect(out, contains('2/2 answered'));
      expect(lookedUp, ['host.example']);
    });

    test('tcpPing: an ordinary network is untouched', () async {
      final out = await tcpPing('0.0.0.9',
          count: 2,
          gap: Duration.zero,
          connect: anyNet,
          lookup: resolver({}));
      expect(out, startsWith('TCP connect to 0.0.0.9 (0.0.0.9) port 443\n'));
      expect(out, contains('2/2 answered'));
      expect(lookedUp, ['0.0.0.9']);
    });

    test('tcpPing: no route and no NAT64 reports each attempt', () async {
      final out = await tcpPing('0.0.0.9',
          count: 2,
          gap: Duration.zero,
          connect: v6Only,
          lookup: resolver({}, nat64: false));
      expect(out, contains('seq=1  no answer (Network is unreachable)'));
      expect(out, contains('seq=2  no answer (Network is unreachable)'));
      expect(out, contains('0/2 answered'));
    });
  });
}
