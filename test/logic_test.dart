import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:fieldkit/src/logic/ipv4.dart';
import 'package:fieldkit/src/logic/mtu.dart';
import 'package:fieldkit/src/logic/xfer.dart';
import 'package:fieldkit/src/logic/diff.dart';
import 'package:fieldkit/src/logic/defang.dart';
import 'package:fieldkit/src/logic/cvss.dart';
import 'package:fieldkit/src/logic/jwtdec.dart';
import 'package:fieldkit/src/logic/hashes.dart';
import 'package:fieldkit/src/logic/timestampx.dart';
import 'package:fieldkit/src/logic/decoder.dart';

void main() {
  group('ipv4 basics', () {
    test('ip2int / int2ip round trip', () {
      expect(ip2int('10.0.0.1'), 0x0A000001);
      expect(int2ip(0x0A000001), '10.0.0.1');
      expect(ip2int('255.255.255.255'), 0xFFFFFFFF);
      expect(ip2int('256.1.1.1'), isNull);
      expect(ip2int('1.2.3'), isNull);
    });
    test('subnetInfo /24', () {
      final s = SubnetInfo.of(ip2int('192.0.2.0')!, 24);
      expect(s.mask, '255.255.255.0');
      expect(s.wildcard, '0.0.0.255');
      expect(s.broadcast, '192.0.2.255');
      expect(s.first, '192.0.2.1');
      expect(s.last, '192.0.2.254');
      expect(s.usable, 254);
    });
    test('subnetInfo /31 and /32', () {
      final s31 = SubnetInfo.of(ip2int('192.0.2.0')!, 31);
      expect(s31.usable, 2);
      expect(s31.broadcast, '—');
      final s32 = SubnetInfo.of(ip2int('192.0.2.5')!, 32);
      expect(s32.usable, 1);
      expect(s32.first, '192.0.2.5');
    });
    test('parseCidr flags host bits', () {
      final p = parseCidr('10.1.2.3/24').value!;
      expect(p.hostBits, isTrue);
      expect(int2ip(p.base), '10.1.2.0');
    });
  });

  group('vlsm', () {
    test('classic allocation, biggest first', () {
      final r = vlsmPlan('192.0.2.0/24', 'users: 100\nservers: 50\np2p: /30');
      expect(r.err, isNull);
      expect(r.rows.length, 3);
      final byName = {for (final s in r.rows) s.name: s};
      expect(byName['users']!.cidr, '192.0.2.0/25');
      expect(byName['servers']!.cidr, '192.0.2.128/26');
      expect(byName['p2p']!.cidr, '192.0.2.192/30');
      expect(r.free, 256 - 128 - 64 - 4);
    });
    test('hosts→len boundary: 2 hosts gets /30', () {
      final r = vlsmPlan('192.0.2.0/29', 'a: 2');
      expect(r.rows.single.len, 30);
    });
    test('overflow reported', () {
      final r = vlsmPlan('192.0.2.0/26', 'a: 100');
      expect(r.err, contains('Does not fit'));
    });
    test('alignment gap: /25 after /26 request order', () {
      final r = vlsmPlan('192.0.2.0/24', 'small: /26\nbig: /25');
      final byName = {for (final s in r.rows) s.name: s};
      expect(byName['big']!.cidr, '192.0.2.0/25');
      expect(byName['small']!.cidr, '192.0.2.128/26');
    });
  });

  group('aggregate', () {
    test('adjacent /24s merge', () {
      final r = aggregate('10.0.0.0/24 10.0.1.0/24');
      expect(r.list, ['10.0.0.0/23']);
    });
    test('three /24s → /23 + /24', () {
      final r = aggregate('192.0.2.0/24\n198.51.100.0/24\n198.51.101.0/24');
      expect(r.list, ['192.0.2.0/24', '198.51.100.0/23']);
    });
    test('contained prefix absorbed', () {
      final r = aggregate('10.0.0.0/8, 10.1.0.0/16');
      expect(r.list, ['10.0.0.0/8']);
    });
    test('bare IP treated as /32, host bits noted', () {
      final r = aggregate('192.0.2.7\n192.0.2.6');
      expect(r.list, ['192.0.2.6/31']);
      final r2 = aggregate('192.0.2.7/24');
      expect(r2.notes.single, contains('host bits'));
      expect(r2.list, ['192.0.2.0/24']);
    });
    test('non-mergeable neighbors stay split', () {
      final r = aggregate('10.0.1.0/24 10.0.2.0/24');
      expect(r.list, ['10.0.1.0/24', '10.0.2.0/24']);
    });
  });

  group('wildcard', () {
    test('cidr → wildcard', () {
      final w = wildcardInfo('10.0.0.0/16');
      expect(w.wildcard, '0.0.255.255');
      expect(w.acl, 'permit ip 10.0.0.0 0.0.255.255 any');
      expect(w.matched, 65536);
    });
    test('contiguous wildcard → cidr', () {
      final w = wildcardInfo('10.0.0.0 0.0.0.255');
      expect(w.cidr, '10.0.0.0/24');
      expect(w.contiguous, isTrue);
    });
    test('discontiguous wildcard flagged', () {
      final w = wildcardInfo('10.0.0.0 0.255.0.255');
      expect(w.contiguous, isFalse);
      expect(w.cidr, isNull);
      expect(w.matched, 1 << 16);
    });
  });

  group('mtu/xfer', () {
    test('gre + ipsec stack', () {
      final sel = encaps.where((e) => e.id == 'gre' || e.id == 'ipsec');
      final r = mtuCalc(1500, sel);
      expect(r.total, 82);
      expect(r.mtu, 1418);
      expect(r.mssV4, 1378);
      expect(r.mssV6, 1358);
    });
    test('transfer time 1 GB @ 1 Gbps 100%', () {
      final r = xferTime(1, 1e9, 1, 1e9, 100);
      expect(r.seconds, closeTo(8, 0.001));
    });
    test('humanDur shapes', () {
      expect(humanDur(0.5), '500 ms');
      expect(humanDur(90), '1m 30s');
      expect(humanDur(86400 * 2 + 3600), '2d 1h');
    });
  });

  group('diff', () {
    List<String> l(String s) => s.isEmpty ? [] : s.split(' ');
    test('identical', () {
      final r = diffLines(l('a b c'), l('a b c'));
      expect(r.changes, 0);
      expect(r.ops.length, 3);
    });
    test('simple replace', () {
      final r = diffLines(l('a b c d'), l('a x c d'));
      expect(r.ops.map((o) => o.t + o.s).toList(),
          [' a', '-b', '+x', ' c', ' d']);
    });
    test('insert and delete', () {
      final r = diffLines(l('a b c'), l('a c d'));
      expect(r.changes, 2);
      expect(r.ops.where((o) => o.t == '-').single.s, 'b');
      expect(r.ops.where((o) => o.t == '+').single.s, 'd');
    });
    test('completely different (d == max path)', () {
      final r = diffLines(l('a'), l('b'));
      expect(r.ops.map((o) => o.t + o.s).toList(), ['-a', '+b']);
    });
    test('empty sides', () {
      expect(diffLines([], l('a b')).changes, 2);
      expect(diffLines(l('a b'), []).changes, 2);
      expect(diffLines([], []).changes, 0);
    });
    test('prepLines options', () {
      final lines = prepLines('int g0/1\n ! comment\n  ip  addr \n',
          dropComments: true, squashWs: true);
      expect(lines, ['int g0/1', 'ip addr']);
    });
    test('a real-ish config change', () {
      const a = 'interface Gi0/1\n ip address 192.0.2.1 255.255.255.0\n no shut\n';
      const b = 'interface Gi0/1\n ip address 192.0.2.2 255.255.255.0\n no shut\n';
      final r = diffLines(prepLines(a), prepLines(b));
      expect(r.changes, 2);
    });
  });

  group('defang/refang', () {
    test('url + ip + email round trip', () {
      const orig =
          'Callback to https://evil-c2.example.com/gate.php from 203.0.113.7, contact bad.actor@example.com';
      final d = defang(orig);
      expect(d, isNot(contains('https://')));
      expect(d, contains('hxxps[://]'));
      expect(d, contains('203[.]0[.]113[.]7')); // ip defanged
      expect(d, contains('[at]'));
      expect(refang(d), orig);
    });
    test('refang common third-party styles', () {
      expect(refang('hxxp://bad(.)example(dot)com'), 'http://bad.example.com');
      expect(refang('198[.]51[.]100[.]9'), '198.51.100.9');
      expect(refang('user(at)example[.]org'), 'user@example.org');
    });
    test('plain prose dots untouched', () {
      expect(defang('patch now. reboot later.'), 'patch now. reboot later.');
    });
  });

  group('cvss v3.1 known vectors', () {
    double score(String v) {
      final p = cvssParse(v);
      expect(p.err, isNull);
      final r = cvssScore(p.m!);
      expect(r.err, isNull);
      return r.score;
    }

    test('9.8 critical (network RCE shape)', () {
      expect(score('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'), 9.8);
    });
    test('10.0 scope changed', () {
      expect(score('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H'), 10.0);
    });
    test('7.8 local privesc shape', () {
      expect(score('CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H'), 7.8);
    });
    test('6.1 reflected xss shape', () {
      expect(score('CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N'), 6.1);
    });
    test('zero impact → 0.0', () {
      expect(score('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N'), 0.0);
    });
    test('severity bands', () {
      expect(cvssSeverity(0), 'None');
      expect(cvssSeverity(3.9), 'Low');
      expect(cvssSeverity(4.0), 'Medium');
      expect(cvssSeverity(8.9), 'High');
      expect(cvssSeverity(9.0), 'Critical');
    });
    test('parse rejects partial vector', () {
      expect(cvssParse('CVSS:3.1/AV:N/AC:L').err, isNotNull);
    });
  });

  group('jwt', () {
    String mk(Map h, Map p) {
      String enc(Map m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      return '${enc(h)}.${enc(p)}.sig';
    }

    test('decodes header and payload', () {
      final r = jwtDecode(mk({'alg': 'HS256', 'typ': 'JWT'},
          {'sub': 'user1', 'exp': 1700000000}));
      expect(r.err, isNull);
      expect(r.header!['alg'], 'HS256');
      expect(r.payload!['sub'], 'user1');
    });
    test('alg none warning', () {
      final r = jwtDecode(mk({'alg': 'none'}, {'sub': 'x'}));
      expect(r.warnings.single, contains('UNSIGNED'));
    });
    test('bearer prefix stripped, bad part count rejected', () {
      expect(jwtDecode('Bearer a.b').err, contains('three'));
    });
  });

  group('hash id + crypto vectors', () {
    test('identification table', () {
      expect(identifyHash('d41d8cd98f00b204e9800998ecf8427e'), contains('MD5'));
      expect(identifyHash('a' * 40), contains('SHA-1'));
      expect(identifyHash('a' * 64), contains('SHA-256'));
      expect(identifyHash('a' * 128), contains('SHA-512'));
      expect(identifyHash(r'$2b$10$abcdefghijklmnopqrstuv'), 'bcrypt');
      expect(identifyHash(r'$6$rounds=5000$saltsalt$hash'), contains('SHA-512 crypt'));
      expect(identifyHash('aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0'),
          contains('LM:NT'));
      expect(identifyHash('SGVsbG8gd29ybGQhIQ=='), contains('Base64'));
    });
    test('md5/sha rfc vectors via package:crypto', () {
      expect(md5.convert(utf8.encode('')).toString(),
          'd41d8cd98f00b204e9800998ecf8427e');
      expect(md5.convert(utf8.encode('abc')).toString(),
          '900150983cd24fb0d6963f7d28e17f72');
      expect(sha1.convert(utf8.encode('abc')).toString(),
          'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(sha256.convert(utf8.encode('abc')).toString(),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('timestamps', () {
    test('epoch seconds', () {
      final r = tsParse('1700000000', 0);
      expect(r.src, contains('seconds'));
      expect(r.ms, 1700000000000);
    });
    test('epoch ms and us', () {
      expect(tsParse('1700000000000', 0).src, contains('milliseconds'));
      expect(tsParse('1700000000000000', 0).ms, 1700000000000);
    });
    test('filetime round trip', () {
      const ms = 1700000000000;
      final ft = (BigInt.from(ms) * BigInt.from(10000) + filetimeEpochDiff)
          .toString();
      final r = tsParse(ft, 0);
      expect(r.src, contains('FILETIME'));
      expect(r.ms, ms);
      expect(tsFormats(ms, ms).filetime, ft);
    });
    test('iso 8601', () {
      final r = tsParse('2026-08-16T12:00:00Z', 0);
      expect(r.ms, DateTime.utc(2026, 8, 16, 12).millisecondsSinceEpoch);
    });
    test('relative wording', () {
      expect(tsRelative(0, 90 * 1000), '2 minutes ago');
      expect(tsRelative(90 * 1000, 0), 'in 2 minutes');
    });
    test('garbage rejected', () {
      expect(tsParse('not a time', 0).err, isNotNull);
    });
  });

  group('decoder workbench', () {
    test('base64 both ways incl urlsafe + missing padding', () {
      expect(b64decode('SGVsbG8').out, 'Hello');
      expect(b64decode('PDw_Pz4-').out, '<<??>>');
      expect(b64encode('Hello').out, 'SGVsbG8=');
    });
    test('hex both ways', () {
      expect(hexToText('48 65 6c 6c 6f').out, 'Hello');
      expect(hexToText('0x486579').out, 'Hey');
      expect(textToHex('Hey').out, '486579');
      expect(hexToText('abc').err, isNotNull);
    });
    test('url encode/decode', () {
      expect(urlDecode('a%20b+c').out, 'a b c');
      expect(urlEncode('a b&c').out, 'a%20b%26c');
      expect(urlDecode('%zz').err, isNotNull);
    });
    test('rot13', () {
      expect(rot13('Uryyb, Jbeyq!').out, 'Hello, World!');
    });
    test('html entities incl numeric', () {
      expect(htmlDecode('&lt;a href=&quot;x&quot;&gt;&amp;&#65;&#x42;').out,
          '<a href="x">&AB');
    });
  });
}
