import 'dart:math';

const double _earthRadius = 6371000;
double _rad(double deg) => deg * pi / 180;

/// Offset from the runner to the ghost in metres, relative to the way the
/// runner is facing: `[right, forward]`.
/// [heading] is degrees clockwise from north (as given by GPS).
List<double> displacement({
  required double originLat,
  required double originLon,
  required double targetLat,
  required double targetLon,
  required double heading,
}) {
  final meanLat = _rad((originLat + targetLat) / 2);
  final east = _rad(targetLon - originLon) * cos(meanLat) * _earthRadius;
  final north = _rad(targetLat - originLat) * _earthRadius;

  final h = _rad(heading);
  return [east * cos(h) - north * sin(h), east * sin(h) + north * cos(h)];
}

/// Volume: 1 within 2m of the ghost, fading to 0 at [range] metres.
double getVolume(List<double> offset, {double range = 100}) {
  final distance = sqrt(offset[0] * offset[0] + offset[1] * offset[1]);
  return 1 - (distance.clamp(2.0, range) - 2.0) / (range - 2.0);
}

/// Metres at which the ghost's footsteps and breathing fade out.
const footstepsRange = 120.0, breathingRange = 50.0;

/// The runner's heartbeat: full when level with the ghost, silent from 20m
/// apart (ahead or behind). It's the runner's own, so not placed or muffled.
double heartbeatVolume(double gap) => getVolume([0, gap], range: 20);

/// Low-pass cutoff in Hz: 16kHz (clear) when the ghost is dead ahead, down to
/// 2kHz (muffled) dead behind. Stereo panning alone can't tell front from back;
/// ears dull sounds from behind, so muffling is the cue. Not lower: the steps'
/// 1-5kHz crunch is what cuts through wind and traffic outdoors.
double lowPassCutoff(List<double> offset) =>
    16000 * pow(2000 / 16000, _behind(offset)).toDouble();

/// Volume multiplier: 1 when the ghost is ahead, up to [boost] dead behind, so
/// a ghost on your heels sounds close despite the muffling.
/// Above 1 is fine: SoLoud doesn't clamp volume, and the sounds peak at -6dB.
double behindGain(List<double> offset, {double boost = 2}) =>
    1 + (boost - 1) * _behind(offset);

/// 0 when [offset] is dead ahead (or on top of the runner) .. 1 dead behind.
double _behind(List<double> offset) {
  final distance = sqrt(offset[0] * offset[0] + offset[1] * offset[1]);
  return distance == 0 ? 0 : (1 - offset[1] / distance) / 2;
}

/// Compass bearing in degrees (0 = north, 90 = east) from point 1 to point 2.
double bearing(double lat1, double lon1, double lat2, double lon2) {
  final east = _rad(lon2 - lon1) * cos(_rad((lat1 + lat2) / 2));
  final north = _rad(lat2 - lat1);
  return (atan2(east, north) * 180 / pi + 360) % 360;
}

/// Empty means "use the original run's pace"; otherwise m:ss or mm:ss per km.
/// Must match parseSpeed in back-end/process_route.js.
bool isValidPace(String pace) =>
    RegExp(r'^(\d{1,2}:[0-5]\d)?$').hasMatch(pace.trim());

/// Converts a JSON route (`[[lon, lat], ...]`) to doubles.
List<List<double>> toPoints(List<dynamic> raw) => [
  for (final point in raw)
    [for (final n in point as List) (n as num).toDouble()],
];

/// Metres between the runner at ([lat], [lon]) and a `[lon, lat]` point.
double _metres(double lat, double lon, List<double> p) {
  final d = displacement(
    originLat: lat,
    originLon: lon,
    targetLat: p[1],
    targetLon: p[0],
    heading: 0,
  );
  return sqrt(d[0] * d[0] + d[1] * d[1]);
}

/// Metres from the start of [route] to each of its points.
List<double> distanceAlong(List<List<double>> route) {
  final along = <double>[0];
  for (var i = 1; i < route.length; i++) {
    along.add(along.last + _metres(route[i - 1][1], route[i - 1][0], route[i]));
  }
  return along;
}

/// Distance between waypoints in metres.
const waypointSpacing = 5.0;

/// Points every [spacing] metres along [route] (with [along] from [distanceAlong]),
/// so waypoint k is k * [spacing] metres from the start.
List<List<double>> waypoints(
  List<List<double>> route,
  List<double> along, {
  double spacing = waypointSpacing,
}) {
  final points = <List<double>>[];
  for (var i = 0; i < route.length; i++) {
    while (points.length * spacing <= along[i]) {
      final a = route[max(i - 1, 0)], b = route[i];
      final t = i == 0
          ? 0.0
          : (points.length * spacing - along[i - 1]) /
                (along[i] - along[i - 1]);
      points.add([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
    }
  }
  return points;
}

/// The `[lon, lat]` point [metres] along the route, from its [waypoints]
/// (k * [spacing] metres from the start), clamped to the start and finish.
List<double> pointAt(
  List<List<double>> waypoints,
  double metres, {
  double spacing = waypointSpacing,
}) {
  final k = (metres / spacing).clamp(0.0, waypoints.length - 1.0);
  final i = k.floor();
  if (i + 1 >= waypoints.length) return waypoints[i];
  final a = waypoints[i], b = waypoints[i + 1], t = k - i;
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
}

/// Tracks how far along the route the runner is. A waypoint only counts once the
/// one before it has, except up to [maxMissed] in a row may be skipped for GPS
/// dropouts, so shortcuts and later laps over the same path don't count.
// shortcut: losing GPS for more than maxMissed waypoints leaves the runner stuck
// until they return to the route there; upgrade to a window that grows with time since the last fix.
class WaypointTracker {
  WaypointTracker(
    this.waypoints, {
    this.spacing = waypointSpacing,
    this.radius = 15,
    this.maxMissed = 10,
  });

  final List<List<double>> waypoints;
  final double spacing, radius;
  final int maxMissed;

  /// Index of the last waypoint reached, -1 before the first.
  int reached = -1;

  /// Metres along the route.
  double metres = 0;

  void update(double lat, double lon) {
    // The closest waypoint within reach, counting the current one so standing still doesn't advance.
    var bestDistance = radius;
    final end = min(reached + maxMissed + 2, waypoints.length);
    for (var k = max(reached, 0); k < end; k++) {
      final d = _metres(lat, lon, waypoints[k]);
      if (d < bestDistance) {
        bestDistance = d;
        reached = k;
      }
    }
    if (reached < 0) return;
    metres = reached * spacing;
    if (reached + 1 < waypoints.length) {
      // Add how far past the waypoint the runner is, so progress is smooth rather than 5m steps.
      final p = waypoints[reached], q = waypoints[reached + 1];
      final ahead = displacement(
        originLat: p[1],
        originLon: p[0],
        targetLat: lat,
        targetLon: lon,
        heading: bearing(p[1], p[0], q[1], q[0]),
      )[1];
      metres += ahead.clamp(-spacing, spacing);
    }
  }
}

/// Smooths a reading that only changes on each GPS fix (~1Hz) into one that
/// moves every tick: each new reading is reached over the time the previous
/// one took to arrive, so the runner glides at their pace about one fix behind.
class Glide {
  double? _from, _to;
  Duration _start = Duration.zero, _length = Duration.zero;

  double update(double reading, Duration now) {
    if (reading != _to) {
      _from = _to == null ? reading : _at(now);
      _length = now - _start;
      _start = now;
      _to = reading;
    }
    return _at(now);
  }

  double _at(Duration now) {
    final t = _length <= Duration.zero
        ? 1.0
        : ((now - _start).inMicroseconds / _length.inMicroseconds).clamp(
            0.0,
            1.0,
          );
    return _from! + (_to! - _from!) * t;
  }
}

/// How far to the side of the runner the ghost's sound passes, in metres.
const passingSide = 1.5;

/// Where to play the ghost, as `[right, forward]` metres: [gap] metres straight
/// ahead (behind if negative), [passingSide] to one [side] (1 right, -1 left),
/// so the sound sweeps round that ear as it overtakes.
List<double> ghostOffset(double gap, int side) => [side * passingSide, gap];

/// Spots overtakes from the gap (metres the ghost is ahead along the route).
class OvertakeDetector {
  OvertakeDetector({this.cooldown = const Duration(seconds: 5)});

  final Duration cooldown;
  bool? _announced; // was the ghost ahead at the last overtake (or the start)
  Duration? _last;

  /// True when the ghost has just overtaken the runner, false when the runner
  /// has just overtaken the ghost, otherwise null. At most one per [cooldown], so
  /// running neck and neck doesn't spam sounds; a pass during the cooldown is
  /// announced once it ends, if it still holds.
  bool? update(double gap, Duration now) {
    if (gap == 0) return null;
    final ahead = gap > 0;
    if (_announced == null) {
      _announced = ahead; // the starting order isn't an overtake
      return null;
    }
    if (ahead == _announced) return null;
    if (_last != null && now - _last! < cooldown) return null;
    _last = now;
    return _announced = ahead;
  }
}

/// Dummy run (desk testing): the tick of the ghost's route the simulated runner is
/// at after [seconds] (whole seconds, like a 1Hz GPS fix). It trails the ghost by a
/// lag swinging between ±[maxLag] seconds, so they swap places every [cycle] seconds,
/// ghost ahead first. maxLag < cycle / π keeps the runner moving forwards.
int dummyRunnerTick(
  int seconds,
  Duration tick,
  int routeLength, {
  double cycle = 75,
  double maxLag = 20,
}) {
  final t = seconds - maxLag * sin(pi * seconds / cycle);
  return (t * 1000 / tick.inMilliseconds).round().clamp(0, routeLength - 1);
}
