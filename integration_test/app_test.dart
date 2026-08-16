// Drives the real app and exercises every tool with a real input.
//
//   flutter test integration_test -d linux    (headless: under xvfb-run)
//
// The live-tool tests use 127.0.0.1, a listener the test opens itself, and
// two stable public endpoints (example.com, 1.1.1.1 DoH) — they need outbound
// network and will fail on an airgapped host, which is the correct signal.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fieldkit/main.dart';

Future<void> openTool(WidgetTester tester, String name) async {
  // The sidebar ListView is lazy AND scrollUntilVisible only sweeps downward,
  // so start from the top every time: deterministic regardless of where the
  // previous tool left the scroll position.
  final scrollable = find.byType(Scrollable).first;
  await tester.drag(scrollable, const Offset(0, 3000));
  await tester.pumpAndSettle();
  final item = find.text(name);
  await tester.scrollUntilVisible(item, 120, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// Pumps until [finder] matches or [timeout] passes — for async tool results
/// that pumpAndSettle cannot wait on (network futures).
Future<void> waitFor(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  // Dump what is actually on screen so a remote failure is diagnosable.
  final seen = <String>{};
  for (final w in tester.allWidgets) {
    if (w is Text && w.data != null) seen.add(w.data!);
    if (w is SelectableText && w.data != null) seen.add(w.data!);
  }
  expect(finder, findsWidgets,
      reason:
          'timed out after $timeout waiting for $finder\nvisible text: ${seen.join(" | ")}');
}

Finder textContains(String fragment) => find.byWidgetPredicate((w) {
      String? data;
      if (w is Text) data = w.data;
      if (w is SelectableText) data = w.data;
      if (data == null && w is RichText) data = w.text.toPlainText();
      if (data == null && w is SelectableText && w.textSpan != null) {
        data = w.textSpan!.toPlainText();
      }
      return data != null && data.contains(fragment);
    });

/// IndexedStack keeps every page in the tree, so hint-based finders can match
/// offstage twins on other pages — hitTestable() keeps only the visible one.
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  final visible = field.hitTestable();
  await tester.ensureVisible(visible);
  await tester.pumpAndSettle();
  await tester.enterText(visible, text);
  await tester.pumpAndSettle();
}

Finder fieldWithHint(String hintFragment) => find.byWidgetPredicate((w) =>
    w is TextField &&
    (w.decoration?.hintText ?? '').contains(hintFragment));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every tool does its job on real input', (tester) async {
    await tester.pumpWidget(const FieldKitApp());
    await tester.pumpAndSettle();

    // ---------- Subnet / VLSM ----------
    // Default page. Plan a /24 split and check the biggest block lands first.
    await typeInto(tester, fieldWithHint('10.0.0.0/24'), '192.0.2.0/24');
    await typeInto(
        tester, fieldWithHint('users: 100'), 'users: 100\nlinks: /30');
    expect(textContains('192.0.2.0/25'), findsWidgets, reason: 'VLSM row');
    expect(textContains('192.0.2.128/30'), findsWidgets, reason: 'p2p row');

    // ---------- CIDR summarizer ----------
    await openTool(tester, 'CIDR summarizer');
    await typeInto(
        tester, fieldWithHint('10.1.0.0/24'), '10.1.0.0/24\n10.1.1.0/24');
    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();
    expect(textContains('10.1.0.0/23'), findsWidgets, reason: 'merged /23');

    // ---------- Wildcard / ACL ----------
    await openTool(tester, 'Wildcard / ACL');
    await typeInto(tester, fieldWithHint('0.0.255.255'), '172.16.0.0/12');
    expect(textContains('0.15.255.255'), findsWidgets, reason: 'wildcard');
    expect(textContains('permit ip 172.16.0.0 0.15.255.255 any'), findsWidgets);

    // ---------- MTU / MSS ----------
    await openTool(tester, 'MTU / MSS');
    final gre = find.text('GRE  —  24 bytes');
    await tester.ensureVisible(gre);
    await tester.pumpAndSettle();
    await tester.tap(gre);
    await tester.pumpAndSettle();
    expect(textContains('1476'), findsWidgets, reason: 'MTU after GRE');
    expect(textContains('1436'), findsWidgets, reason: 'v4 MSS after GRE');

    // ---------- Transfer time ----------
    await openTool(tester, 'Transfer time');
    // Defaults: 500 GB @ 1 Gbps, 94% — just assert a result rendered.
    expect(textContains('Transfer time'), findsWidgets);
    expect(textContains('h '), findsWidgets, reason: '500GB@1Gbps ≈ 1h+');

    // ---------- Config diff ----------
    await openTool(tester, 'Config diff');
    await typeInto(tester, fieldWithHint('before / running-config'),
        'interface Gi0/1\n ip address 192.0.2.1 255.255.255.0\n');
    await typeInto(tester, fieldWithHint('after / candidate config'),
        'interface Gi0/1\n ip address 192.0.2.99 255.255.255.0\n');
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(textContains('2 changed lines'), findsWidgets);

    // ---------- Ping (system ping, loopback) ----------
    await openTool(tester, 'Ping');
    await typeInto(tester, fieldWithHint('host or IP'), '127.0.0.1');
    await tester.tap(find.widgetWithText(FilledButton, 'Ping').hitTestable());
    // 'from 127.0.0.1' only appears in real ping output (Linux "64 bytes from",
    // Windows "Reply from") — the bare IP would also match the input field.
    await waitFor(tester, textContains('from 127.0.0.1'),
        timeout: const Duration(seconds: 30));

    // ---------- Port check (against our own listener) ----------
    final listener = await ServerSocket.bind('127.0.0.1', 0);
    await openTool(tester, 'Port check');
    await typeInto(
        tester, fieldWithHint('host or IP'), '127.0.0.1');
    await typeInto(tester, fieldWithHint('22, 80, 443'), '${listener.port}');
    await tester.tap(find.text('Check'));
    await waitFor(tester, textContains('OPEN'));
    await listener.close();

    // ---------- DNS lookup (system + DoH) ----------
    await openTool(tester, 'DNS lookup');
    await typeInto(tester, fieldWithHint('example.com'), 'example.com');
    await tester.tap(find.text('Look up').hitTestable());
    await tester.pump(const Duration(milliseconds: 300));
    await waitFor(tester, textContains('DNS over HTTPS'));

    // ---------- TLS certificate ----------
    await openTool(tester, 'TLS certificate');
    await typeInto(tester, fieldWithHint('example.com'), 'example.com');
    await tester.tap(find.text('Inspect'));
    await waitFor(tester, find.text('Issuer'));
    expect(textContains('Days left'), findsWidgets);

    // ---------- Local interfaces (auto-runs) ----------
    await openTool(tester, 'Local interfaces');
    await waitFor(tester, textContains('.'), timeout: const Duration(seconds: 5));

    // ---------- Public IP (our own service) ----------
    await openTool(tester, 'Public IP');
    await tester.tap(find.text('Check my public IP'));
    await waitFor(tester, find.text('ip'));

    // ---------- Defang / refang ----------
    await openTool(tester, 'Defang / refang');
    await typeInto(tester, fieldWithHint('malicious.example.com'),
        'https://bad.example.com/x.php from 203.0.113.9');
    await tester.tap(find.text('Defang'));
    await tester.pumpAndSettle();
    expect(textContains('hxxps[://]bad[.]example[.]com'), findsWidgets);
    expect(textContains('203[.]0[.]113[.]9'), findsWidgets);

    // ---------- CVSS ----------
    await openTool(tester, 'CVSS calculator');
    await typeInto(tester, fieldWithHint('CVSS:3.1/'),
        'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H');
    await tester.tap(find.text('Parse'));
    await tester.pumpAndSettle();
    expect(find.text('9.8'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);

    // ---------- JWT ----------
    await openTool(tester, 'JWT decoder');
    String b64(Map m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final tok =
        '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': 'fieldkit-test', 'exp': 1500000000})}.sig';
    await typeInto(tester, fieldWithHint('eyJhbGciOi'), tok);
    expect(textContains('fieldkit-test'), findsWidgets);
    expect(textContains('EXPIRED'), findsWidgets, reason: '2017 exp is past');

    // ---------- Hashes ----------
    await openTool(tester, 'Hashes');
    await typeInto(tester, fieldWithHint('text to hash'), 'abc');
    expect(
        textContains(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
        findsWidgets,
        reason: 'sha256("abc")');
    await typeInto(tester, fieldWithHint('vendor-published'),
        '900150983cd24fb0d6963f7d28e17f72');
    expect(textContains('Matches MD5'), findsWidgets);

    // ---------- Timestamps ----------
    await openTool(tester, 'Timestamps');
    await typeInto(tester, fieldWithHint('1755316800'), '1700000000');
    expect(textContains('2023-11-14T22:13:20'), findsWidgets);

    // ---------- Decoder workbench ----------
    await openTool(tester, 'Decoder workbench');
    await typeInto(tester, fieldWithHint('cG93ZXJzaGVsbCA'), 'SGVsbG8sIFdvcmxkIQ==');
    await tester.tap(find.text('Base64 → text'));
    await tester.pumpAndSettle();
    expect(textContains('Hello, World!'), findsWidgets);

    // ---------- v1.1: Traceroute (loopback) ----------
    await openTool(tester, 'Traceroute');
    await typeInto(tester, fieldWithHint('host or IP'), '127.0.0.1');
    await tester.tap(find.text('Trace').hitTestable());
    await waitFor(tester, textContains('hops'),
        timeout: const Duration(seconds: 45)); // "hops max" / "of 30 hops"

    // ---------- v1.1: Whois (live, follows referrals) ----------
    await openTool(tester, 'Whois');
    await typeInto(tester, fieldWithHint('example.com or'), 'example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Whois').hitTestable());
    await waitFor(tester, textContains('===== whois.iana.org'),
        timeout: const Duration(seconds: 40));

    // ---------- v1.1: MAC / OUI (bundled IEEE registry) ----------
    await openTool(tester, 'MAC / OUI lookup');
    await typeInto(tester, fieldWithHint('28:6f:b9'), '28:6f:b9:00:00:01');
    await waitFor(tester, textContains('Nokia'),
        timeout: const Duration(seconds: 10));

    // ---------- v1.1: IOC extractor (defanged in, defanged report out) ----------
    await openTool(tester, 'IOC extractor');
    await typeInto(tester, fieldWithHint('paste anything'),
        'beacon hxxps[://]evil[.]example[.]com/g.php from 203[.]0[.]113[.]7, CVE-2026-1111');
    await tester.tap(find.text('Extract').hitTestable());
    await tester.pumpAndSettle();
    expect(textContains('203[.]0[.]113[.]7'), findsWidgets);
    expect(textContains('CVE-2026-1111'), findsWidgets);
    expect(textContains('# URLs (1)'), findsWidgets);

    // ---------- v1.1: Email header analyzer ----------
    await openTool(tester, 'Email headers');
    const hdr = 'Return-Path: <bounce@bulk.example.net>\n'
        'Received: from edge.example.org (edge.example.org [198.51.100.7])'
        ' by mx.dest.example; Sat, 16 Aug 2026 02:04:00 -0400\n'
        'Received: from sender.example.net (sender.example.net [203.0.113.20])'
        ' by edge.example.org; Sat, 16 Aug 2026 02:00:00 -0400\n'
        'From: CEO <ceo@corp.example.com>\n'
        'Subject: urgent wire\n'
        'Authentication-Results: mx; spf=pass; dkim=fail; dmarc=pass\n';
    await typeInto(tester, fieldWithHint('Received: from'), hdr);
    await tester.tap(find.text('Analyze').hitTestable());
    await tester.pumpAndSettle();
    expect(textContains('203.0.113.20'), findsWidgets);
    expect(textContains('pass / fail / pass'), findsWidgets);
    expect(textContains('Return-Path'), findsWidgets);

    // ---------- v1.1: IPv6 in the subnet + summarizer tools ----------
    await openTool(tester, 'Subnet / VLSM');
    await typeInto(tester, fieldWithHint('10.0.0.0/24'), '2001:db8::/64');
    expect(textContains('2001:db8::ffff:ffff:ffff:ffff'), findsWidgets);

    await openTool(tester, 'CIDR summarizer');
    await typeInto(tester, fieldWithHint('10.1.0.0/24'),
        '2001:db8::/33\n2001:db8:8000::/33\n10.9.0.0/24');
    await tester.tap(find.text('Summarize').hitTestable());
    await tester.pumpAndSettle();
    expect(textContains('2001:db8::/32'), findsWidgets);
    expect(textContains('10.9.0.0/24'), findsWidgets);
  });
}
