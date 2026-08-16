import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldkit/main.dart';

void main() {
  testWidgets('shell renders all tools and switches pages', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FieldKitApp());
    await tester.pumpAndSettle();

    // Sidebar groups and a few entries.
    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('Subnet / VLSM'), findsOneWidget);
    expect(find.text('CVSS calculator'), findsOneWidget);

    // Default page is the subnet tool with its initial /24 result.
    expect(find.text('Subnet calculator / VLSM splitter'), findsOneWidget);
    expect(find.text('255.255.255.0'), findsWidgets);

    // Switch to CVSS: all-None metrics score 0.0.
    await tester.ensureVisible(find.text('CVSS calculator'));
    await tester.tap(find.text('CVSS calculator'));
    await tester.pumpAndSettle();
    expect(find.text('CVSS v3.1 calculator'), findsOneWidget);
    expect(find.text('0.0'), findsOneWidget);

    // Switch to the decoder and confirm it renders.
    await tester.ensureVisible(find.text('Decoder workbench'));
    await tester.tap(find.text('Decoder workbench'));
    await tester.pumpAndSettle();
    expect(find.text('Base64 → text'), findsOneWidget);
  });
}
