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
    test('audible at 80m', () => expect(getVolume([0, 80]), greaterThan(0)));
    test('silent at 100m and beyond', () => expect(getVolume([0, 120]), 0));
    test('half way', () => expect(getVolume([0, 51]), closeTo(0.5, 0.001)));
    test('custom range', () {
      expect(getVolume([0, 21], range: 40), closeTo(0.5, 0.001));
      expect(getVolume([0, 40], range: 40), 0);
    });
  });

  group('lowPassCutoff', () {
    test('ahead is unfiltered', () => expect(lowPassCutoff([0, 10]), 16000));
    test(
      'behind is muffled',
      () => expect(lowPassCutoff([0, -10]), closeTo(600, 0.01)),
    );
    test('side is in between', () {
      final side = lowPassCutoff([10, 0]);
      expect(side, lessThan(16000));
      expect(side, greaterThan(600));
    });
    test('more muffled the further behind', () {
      expect(lowPassCutoff([10, -5]), lessThan(lowPassCutoff([10, 5])));
    });
    test(
      'on top of the runner counts as ahead',
      () => expect(lowPassCutoff([0, 0]), 16000),
    );
  });

  group('behindGain', () {
    test('ahead is unchanged', () => expect(behindGain([0, 10]), 1));
    test('dead behind is doubled', () => expect(behindGain([0, -10]), 2));
    test('more boost the further behind', () {
      expect(behindGain([1.5, -10]), greaterThan(behindGain([1.5, -1])));
    });
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
    expect(
      toPoints([
        [1, 2],
        [3.5, 4],
      ]),
      [
        [1.0, 2.0],
        [3.5, 4.0],
      ],
    );
  });

  // A straight 100m track due north, as [lon, lat] points 1m apart.
  final track = [
    for (var m = 0; m <= 100; m++) [0.0, m * tenMetresLat / 10],
  ];
  double lat(double metres) => metres * tenMetresLat / 10;

  group('distanceAlong and waypoints', () {
    test('cumulative metres', () {
      final along = distanceAlong(track);
      expect(along.first, 0);
      expect(along.last, closeTo(100, 0.1));
    });
    test('waypoints every 5m, interpolated between sparse points', () {
      final sparse = [track[0], track[100]];
      final wps = waypoints(sparse, distanceAlong(sparse));
      expect(wps.length, 20); // 0..95m: the track is a hair under 100m
      expect(wps[3][1], closeTo(lat(15), 1e-9));
    });
  });

  group('WaypointTracker', () {
    WaypointTracker tracker() =>
        WaypointTracker(waypoints(track, distanceAlong(track)));

    test('follows the runner along the route, smoothly between waypoints', () {
      final t = tracker();
      for (var m = 0.0; m <= 42; m += 3) {
        t.update(lat(m), 0);
      }
      expect(t.metres, closeTo(42, 0.1));
    });
    test('standing still does not advance', () {
      final t = tracker()..update(lat(10), 0);
      for (var k = 0; k < 20; k++) {
        t.update(lat(10), 0);
      }
      expect(t.reached, 2);
    });
    test('tolerates a GPS gap of up to 10 missed waypoints', () {
      final t = tracker()
        ..update(lat(0), 0)
        ..update(lat(55), 0);
      expect(t.reached, 11);
    });
    test('ignores jumps further ahead (shortcuts, later laps)', () {
      final t = tracker()
        ..update(lat(0), 0)
        ..update(lat(80), 0);
      expect(t.reached, 0);
    });
    test('ignores positions far off the route', () {
      final t = tracker()..update(lat(5), 100 * tenMetresLat / 10);
      expect(t.reached, -1);
      expect(t.metres, 0);
    });
  });

  test('ghostOffset places the ghost ahead/behind, off to one side', () {
    expect(ghostOffset(10, 1), [passingSide, 10]);
    expect(ghostOffset(-3, -1), [-passingSide, -3]);
  });

  group('OvertakeDetector', () {
    Duration s(int seconds) => Duration(seconds: seconds);

    test('the starting order is not an overtake', () {
      expect(OvertakeDetector().update(5, s(0)), isNull);
    });
    test('reports who overtook', () {
      final d = OvertakeDetector()..update(-5, s(0));
      expect(d.update(1, s(1)), isTrue);
      expect(d.update(2, s(10)), isNull);
      expect(d.update(-1, s(20)), isFalse);
    });
    test('at most one per cooldown; a pass that holds is announced after', () {
      final d = OvertakeDetector()..update(-5, s(0));
      expect(d.update(1, s(1)), isTrue);
      expect(d.update(-1, s(2)), isNull);
      expect(d.update(-1, s(5)), isNull);
      expect(d.update(-1, s(6)), isFalse);
    });
    test('neck and neck flip-flops during the cooldown stay quiet', () {
      final d = OvertakeDetector()..update(-5, s(0));
      expect(d.update(1, s(1)), isTrue);
      expect(d.update(-1, s(2)), isNull);
      expect(d.update(1, s(7)), isNull);
    });
  });

  group('dummyRunnerTick', () {
    const tick = Duration(milliseconds: 50);
    // Seconds into the ghost's route the runner has reached.
    double at(int s) => dummyRunnerTick(s, tick, 100000) * 0.05;

    test('starts with the ghost', () => expect(at(0), 0));

    test('swaps places every cycle: ghost ahead, then runner ahead', () {
      expect(at(37), lessThan(37 - 15)); // ghost ahead
      expect(at(112), greaterThan(112 + 15)); // runner ahead
      expect(at(187), lessThan(187 - 15)); // ghost ahead again
    });

    test('never runs backwards', () {
      for (var s = 1; s < 400; s++) {
        expect(at(s), greaterThan(at(s - 1)));
      }
    });

    test('stops at the end of the route', () {
      expect(dummyRunnerTick(1000, tick, 50), 49);
    });
  });
}
