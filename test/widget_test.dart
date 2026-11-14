import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldkit/main.dart';
import 'package:fieldkit/src/shell.dart' show appVersion;

// The sidebar is a lazy ListView — items near the bottom are not built until
// scrolled near, so every lookup scrolls first.
Future<void> showItem(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(find.text(name), 120,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  test('the version in the footer is the one in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true)
        .firstMatch(pubspec)![1];
    expect(appVersion, v);
  });

  testWidgets('shell renders all tools and switches pages', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FieldKitApp());
    await tester.pumpAndSettle();

    // Sidebar groups and a few entries.
    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('Subnet / VLSM'), findsOneWidget);

    // The footer links to the privacy policy (both stores require it in-app).
    expect(find.text('Privacy policy'), findsOneWidget);

    // Default page is the subnet tool with its initial /24 result.
    expect(find.text('Subnet calculator / VLSM splitter'), findsOneWidget);
    expect(find.text('255.255.255.0'), findsWidgets);

    // Switch to CVSS: all-None metrics score 0.0.
    await showItem(tester, 'CVSS calculator');
    await tester.tap(find.text('CVSS calculator'));
    await tester.pumpAndSettle();
    expect(find.text('CVSS v3.1 calculator'), findsOneWidget);
    expect(find.text('0.0'), findsOneWidget);

    // Switch to the decoder and confirm it renders.
    await showItem(tester, 'Decoder workbench');
    await tester.tap(find.text('Decoder workbench'));
    await tester.pumpAndSettle();
    expect(find.text('Base64 → text'), findsOneWidget);

    // The v1.1 additions are present in the sidebar.
    for (final name in [
      'Traceroute', 'Whois', 'MAC / OUI lookup', 'IOC extractor', 'Email headers'
    ]) {
      await showItem(tester, name);
      expect(find.text(name), findsOneWidget);
    }
  });
}
