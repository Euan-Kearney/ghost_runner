import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_runner/run_math.dart';

void main() {
  // ~10m of latitude
  const tenMetresLat = 10 / 111195;

  group('displacement', () {
    test('ghost due north while facing north is straight ahead', () {
      final d = displacement(
        originLat: 0,
        originLon: 0,
        targetLat: tenMetresLat,
        targetLon: 0,
        heading: 0,
      );
      expect(d[0], closeTo(0, 0.01));
      expect(d[1], closeTo(10, 0.05));
    });

    test('ghost due north while facing east is on the left', () {
      final d = displacement(
        originLat: 0,
        originLon: 0,
        targetLat: tenMetresLat,
        targetLon: 0,
        heading: 90,
      );
      expect(d[0], closeTo(-10, 0.05));
      expect(d[1], closeTo(0, 0.01));
    });

    test('ghost due north while facing south is behind', () {
      final d = displacement(
        originLat: 0,
        originLon: 0,
        targetLat: tenMetresLat,
        targetLon: 0,
        heading: 180,
      );
      expect(d[1], closeTo(-10, 0.05));
    });
  });

  group('getVolume', () {
    test('full volume up close', () => expect(getVolume([1, 1]), 1));
    test('silent at 50m and beyond', () => expect(getVolume([0, 80]), 0));
    test('half way', () => expect(getVolume([0, 26]), closeTo(0.5, 0.001)));
  });

  group('bearing', () {
    test('north', () => expect(bearing(0, 0, 1, 0), closeTo(0, 1e-9)));
    test('east', () => expect(bearing(0, 0, 0, 1), closeTo(90, 1e-9)));
    test('south', () => expect(bearing(0, 0, -1, 0), closeTo(180, 1e-9)));
    test('west', () => expect(bearing(0, 0, 0, -1), closeTo(270, 1e-9)));
  });

  group('isValidPace', () {
    for (final pace in ['', '05:30', '5:30', '12:00', ' 06:15 ']) {
      test('accepts "$pace"', () => expect(isValidPace(pace), isTrue));
    }
    for (final pace in ['abc', '5:75', '5', '05:3', '-5:00', '00:00x']) {
      test('rejects "$pace"', () => expect(isValidPace(pace), isFalse));
    }
  });

  test('toPoints converts JSON numbers to doubles', () {
    expect(toPoints([
      [1, 2],
      [3.5, 4],
    ]), [
      [1.0, 2.0],
      [3.5, 4.0],
    ]);
  });
}
