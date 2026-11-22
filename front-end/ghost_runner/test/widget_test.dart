import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghost_runner/main.dart';

void main() {
  testWidgets('GO is disabled until a route is chosen', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('GHOST RUNNER'), findsOneWidget);
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

  testWidgets('long button labels stay on one line inside the circle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NeonButton(label: 'RESUME', onPressed: () {}),
        ),
      ),
    );
    final label = tester.getRect(find.text('RESUME'));
    final button = tester.getRect(find.byType(NeonButton));
    expect(label.height, lessThan(40)); // one line of 24px text, not two
    expect(
      button.contains(label.topLeft) && button.contains(label.bottomRight),
      isTrue,
    );
  });
}
