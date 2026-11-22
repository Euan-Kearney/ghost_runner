import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ghost_runner/run_page.dart';

/// iOS only works when the Dart side and ios/Runner agree; these catch one half being removed.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iOS keeps GPS running with the screen locked', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final settings = runLocationSettings();
    expect(settings, isA<AppleSettings>());
    settings as AppleSettings;
    expect(settings.allowBackgroundLocationUpdates, isTrue);
    expect(settings.pauseLocationUpdatesAutomatically, isFalse);
    expect(settings.activityType, ActivityType.fitness);
    expect(settings.accuracy, LocationAccuracy.best);
  });

  test('other platforms use plain best-accuracy settings', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final settings = runLocationSettings();
    expect(settings, isNot(isA<AppleSettings>()));
    expect(settings.accuracy, LocationAccuracy.best);
  });

  test('Info.plist has the background modes and location strings', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final modes = RegExp(
      r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist)!.group(1)!;
    expect(modes, contains('<string>audio</string>'));
    expect(modes, contains('<string>location</string>'));
    expect(plist, contains('NSLocationWhenInUseUsageDescription'));
    expect(plist, contains('NSLocationAlwaysAndWhenInUseUsageDescription'));
    expect(plist, contains('NSLocalNetworkUsageDescription'));
  });

  test('AppDelegate sets a playback audio session (silent switch, screen lock)', () {
    // flutter_soloud leaves the AVAudioSession to the app; the default category
    // is muted by the silent switch and stops when the screen locks.
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('setCategory(.playback'));
    expect(delegate, contains('.mixWithOthers'));
  });
}
