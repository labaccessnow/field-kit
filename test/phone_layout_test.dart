// Phone layout: every tool page, and the app shell, must lay out on a phone
// screen with no overflow (a RenderFlex overflow fails the test).
//
// Sizes are logical pixels: a small Android phone and a current iPhone.
// The 1.3x text-scale run covers people who use larger system text.
import 'package:fieldkit/main.dart';
import 'package:fieldkit/src/theme.dart';
import 'package:fieldkit/src/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const phones = {
  'small phone 360x740': Size(360, 740),
  'iPhone 390x844': Size(390, 844),
};

void setPhone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  for (final phone in phones.entries) {
    for (final scale in [1.0, 1.3]) {
      for (final t in tools) {
        testWidgets('${t.name} fits a ${phone.key} at text x$scale',
            (tester) async {
          setPhone(tester, phone.value);
          await tester.pumpWidget(MaterialApp(
            theme: fieldKitTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  size: phone.value, textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: t.page),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('app opens as a tool list on a ${phone.key}', (tester) async {
      setPhone(tester, phone.value);
      await tester.pumpWidget(const FieldKitApp());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('NETWORK'), findsOneWidget);
      // The privacy link sits under the list.
      await tester.scrollUntilVisible(find.text('Privacy policy'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Privacy policy'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      // Opening a tool pushes it full screen with a back button.
      await tester.tap(find.text('Subnet / VLSM'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
