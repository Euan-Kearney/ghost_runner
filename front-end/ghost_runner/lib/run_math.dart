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

/// Low-pass cutoff in Hz: 16kHz (clear) when the ghost is dead ahead, down to
/// 600Hz (muffled) dead behind. Stereo panning alone can't tell front from
/// back; ears dull sounds from behind, so muffling is the cue.
double lowPassCutoff(List<double> offset) {
  final distance = sqrt(offset[0] * offset[0] + offset[1] * offset[1]);
  if (distance == 0) return 16000;
  final behind = (1 - offset[1] / distance) / 2; // 0 ahead .. 1 behind
  return 16000 * pow(600 / 16000, behind).toDouble();
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
