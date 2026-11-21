import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghost_runner/main.dart';

void main() {
  testWidgets('GO is disabled until a route is chosen', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Ghost Runner'), findsOneWidget);
    final go = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'GO'),
    );
    expect(go.onPressed, isNull);
  });

  testWidgets('no overflow in a small desktop window', (tester) async {
    tester.view.physicalSize = const Size(537, 415);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MyApp());
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an error for an invalid pace', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField), '5:99');
    await tester.pump();
    expect(find.textContaining('mm:ss'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '5:30');
    await tester.pump();
    expect(find.textContaining('mm:ss'), findsNothing);
  });
}
