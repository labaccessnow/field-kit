import 'package:flutter_test/flutter_test.dart';

import 'package:fieldkit/src/logic/emailheader.dart';
import 'package:fieldkit/src/logic/ioc.dart';
import 'package:fieldkit/src/logic/ipv6.dart';
import 'package:fieldkit/src/logic/oui.dart';

void main() {
  group('ipv6 parse/format', () {
    test('loopback and zeros', () {
      expect(parse6('::1'), BigInt.one);
      expect(compress6(BigInt.one), '::1');
      expect(compress6(BigInt.zero), '::');
    });
    test('rfc 5952 canonical forms', () {
      expect(compress6(parse6('2001:db8:0:0:0:0:2:1')!), '2001:db8::2:1');
      expect(compress6(parse6('2001:db8:0:1:1:1:1:1')!),
          '2001:db8:0:1:1:1:1:1'); // single zero group stays
      expect(compress6(parse6('2001:0:0:1:0:0:0:1')!),
          '2001:0:0:1::1'); // longer run wins
      expect(compress6(parse6('2001:db8:0:0:1:0:0:1')!),
          '2001:db8::1:0:0:1'); // first run wins a tie
    });
    test('embedded ipv4 and zone index', () {
      expect(expand6(parse6('::ffff:192.0.2.1')!),
          '0000:0000:0000:0000:0000:ffff:c000:0201');
      expect(parse6('fe80::1%eth0'), isNotNull);
    });
    test('rejects non-addresses', () {
      expect(parse6('12:30:45'), isNull);
      expect(parse6('1::2::3'), isNull);
      expect(parse6('1:2:3:4:5:6:7:8:9'), isNull);
      expect(parse6('gg::1'), isNull);
    });
    test('cidr + subnet info', () {
      final c = parseCidr6('2001:db8::1/64')!;
      expect(c.hostBits, isTrue);
      final info = subnet6Info(parseCidr6('2001:db8::/64')!);
      expect(info.cidr, '2001:db8::/64');
      expect(info.last, '2001:db8::ffff:ffff:ffff:ffff');
      expect(info.count, '18446744073709551616');
    });
    test('aggregation merges halves', () {
      final r = aggregate6([
        parseCidr6('2001:db8::/33')!,
        parseCidr6('2001:db8:8000::/33')!,
      ]);
      expect(r, ['2001:db8::/32']);
      final r2 = aggregate6([
        parseCidr6('2001:db8::/48')!,
        parseCidr6('2001:db8:2::/48')!,
      ]);
      expect(r2, ['2001:db8::/48', '2001:db8:2::/48']);
    });
  });

  group('ioc extraction', () {
    const blob = '''
Callback hxxps[://]evil[.]example[.]com/x.php then 203[.]0[.]113[.]9 twice:
203.0.113.9 — plus v6 C2 2001:db8::bad and mailto bad.actor@example.com.
Dropper a.exe, hash d41d8cd98f00b204e9800998ecf8427e, id
12345678901234567890123456789012 (not a hash), tracked as CVE-2026-12345.
sha256 ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
''';
    test('finds every type, refangs, dedupes, filters', () {
      final r = extractIocs(blob);
      expect(r.urls, ['https://evil.example.com/x.php']);
      expect(r.ips, ['203.0.113.9']); // deduped
      expect(r.ips6, ['2001:db8::bad']);
      expect(r.emails, ['bad.actor@example.com']);
      expect(r.domains, contains('evil.example.com'));
      expect(r.domains, isNot(contains('a.exe')));
      expect(r.domains, isNot(contains('x.php')));
      expect(r.md5, ['d41d8cd98f00b204e9800998ecf8427e']);
      expect(r.sha256,
          ['ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad']);
      expect(r.cves, ['CVE-2026-12345']);
    });
    test('report re-defangs for sharing', () {
      final rep = iocReport(extractIocs(blob));
      expect(rep, contains('203[.]0[.]113[.]9'));
      expect(rep, contains('hxxps[://]'));
      expect(rep, contains('# SHA-256 (1)'));
    });
  });

  group('email headers', () {
    const raw = '''
Return-Path: <bounce@bulk.example.net>
Received: from edge.example.org (edge.example.org [198.51.100.7])
\tby mx.destination.example; Sat, 16 Aug 2026 02:04:00 -0400
Received: from internal.relay (internal.relay [10.0.0.5])
\tby edge.example.org; Sat, 16 Aug 2026 02:02:00 -0400
Received: from sender.example.net (sender.example.net [203.0.113.20])
\tby internal.relay; Sat, 16 Aug 2026 02:00:00 -0400
From: Alex Accountant <ceo@corp.example.com>
Reply-To: attacker@evil.example.net
Subject: urgent wire
Authentication-Results: mx.destination.example; spf=pass
\tsmtp.mailfrom=bulk.example.net; dkim=fail header.d=corp.example.com;
\tdmarc=pass header.from=corp.example.com
''';
    test('chronological hops with delays and origin ip', () {
      final a = analyzeHeaders(raw);
      expect(a.hops.length, 3);
      expect(a.hops.first.from, 'sender.example.net'); // earliest first
      expect(a.hops[1].delaySec, 120);
      expect(a.hops[2].delaySec, 120);
      expect(a.originIp, '203.0.113.20'); // first public in the chain
    });
    test('auth verdicts and phishing warnings', () {
      final a = analyzeHeaders(raw);
      expect(a.spf, 'pass');
      expect(a.dkim, 'fail');
      expect(a.dmarc, 'pass');
      expect(a.warnings.join(' '), contains('DKIM'));
      expect(a.warnings.join(' '), contains('Return-Path'));
      expect(a.warnings.join(' '), contains('Reply-To'));
    });
    test('rfc2822 date parsing', () {
      expect(parseRfc2822('Sat, 16 Aug 2026 02:00:00 -0400'),
          DateTime.utc(2026, 8, 16, 6));
      expect(parseRfc2822('1 Jan 99 12:00:00 GMT'),
          DateTime.utc(1999, 1, 1, 12));
      expect(parseRfc2822('garbage'), isNull);
    });
  });

  group('oui', () {
    final db = parseOuiDb(
        '286FB9\tNokia Shanghai Bell Co., Ltd.\n38E2CA\tKatun Corporation');
    test('lookup with any separator style', () {
      expect(lookupOui(db, '28:6f:b9:aa:bb:cc').vendor, contains('Nokia'));
      expect(lookupOui(db, '38-E2-CA-00-11-22').vendor, 'Katun Corporation');
      expect(lookupOui(db, '286f.b9aa.bbcc').vendor, contains('Nokia'));
    });
    test('flags instead of bogus vendors', () {
      final rand = lookupOui(db, '02:00:00:00:00:01');
      expect(rand.vendor, isNull);
      expect(rand.locallyAdministered, isTrue);
      expect(lookupOui(db, '01:00:5e:00:00:01').multicast, isTrue);
      expect(lookupOui(db, 'zz').err, isNotNull);
    });
  });
}
