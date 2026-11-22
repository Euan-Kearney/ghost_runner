import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_runner/run_page.dart';

void main() {
  testWidgets('run page shows the route map with the ghost, on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844); // iPhone-sized
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // ~100m north. SoLoud isn't initialised in tests, so the page lands on its error state.
    final route = [
      for (var i = 0; i < 200; i++) [0.0, i * 0.0000045],
    ];
    await tester.pumpWidget(
      MaterialApp(home: RunPage(route: route, dummy: true)),
    );
    await tester.pump();

    expect(find.text('👻'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
