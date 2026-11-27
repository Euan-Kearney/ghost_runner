import 'dart:convert';

import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ghost_runner/main.dart';
import 'package:ghost_runner/run_page.dart';

/// Picks a dummy GPX file without a dialog.
class _FakePicker extends FilePickerPlatform {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async => FilePickerResult([
    PlatformFile(name: 'run.gpx', size: 5, bytes: utf8.encode('<gpx/>')),
  ]);
}

/// Opens the home page and picks a GPX, the fake server answering every upload with [response].
Future<void> pickGpx(
  WidgetTester tester,
  Map<String, Object?> response,
  Future<void> Function() then,
) => http.runWithClient(() async {
  FilePickerPlatform.instance = _FakePicker();
  await tester.pumpWidget(const MyApp());
  await tester.tap(find.text('GPX'));
  await tester.pumpAndSettle();
  await then();
}, () => MockClient((_) async => http.Response(jsonEncode(response), 200)));

SwitchListTile elevationToggle(WidgetTester tester) =>
    tester.widget(find.widgetWithText(SwitchListTile, 'Adjust for elevation'));

void main() {
  testWidgets('elevation is locked off when the GPX has none', (tester) async {
    await pickGpx(
      tester,
      {
        'route': [
          [0, 0],
          [0, 0.001],
        ],
        'noElevation': true,
      },
      () async {
        await tester.enterText(find.byType(TextField), '5:30');
        await tester.pumpAndSettle();

        expect(elevationToggle(tester).onChanged, isNull);
        expect(elevationToggle(tester).value, isFalse);
        expect(find.text('Elevation unavailable'), findsOneWidget);
      },
    );
  });

  testWidgets('a GPX without timestamps needs a pace to start', (tester) async {
    const error = 'Enter a pace: this GPX has no timestamps';
    await pickGpx(tester, {'route': null, 'noTimestamps': true}, () async {
      expect(find.text(error), findsNothing);
      expect(
        find.text('GPX file has no timestamps, so enter a pace instead'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text(error), findsOneWidget);
      expect(find.byType(RunPage), findsNothing);

      await tester.enterText(find.byType(TextField), '5:30');
      await tester.pumpAndSettle();
      expect(find.text(error), findsNothing);
    });
  });

  testWidgets('Start is disabled until a route is chosen', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('GHOST RUNNER'), findsOneWidget);
    final go = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
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

  testWidgets('adjust for elevation needs a pace', (tester) async {
    await tester.pumpWidget(const MyApp());
    SwitchListTile toggle() => tester.widget(
      find.widgetWithText(SwitchListTile, 'Adjust for elevation'),
    );

    expect(toggle().onChanged, isNull);

    await tester.enterText(find.byType(TextField), '5:30');
    await tester.pump();
    expect(toggle().onChanged, isNotNull);

    await tester.enterText(find.byType(TextField), '5:99');
    await tester.pump();
    expect(toggle().onChanged, isNull);
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
