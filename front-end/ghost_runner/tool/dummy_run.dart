/// Renders what a dummy run sounds like in the app, without opening it: the
/// ghost follows a GPX route and the simulated runner (dummyRunnerTick) swaps
/// places with it, tracked by the same waypoint, gap, side and overtake logic as
/// the app. Builds the route with back-end/process_route.js, so needs node (with
/// back-end's npm packages installed) and ffmpeg on PATH; the server needn't run.
///
///   dart run tool/dummy_run.dart --gpx=../../back-end/example-routes/Afternoon_Run.gpx --pace=05:30
///
/// Options:
///   --gpx=FILE      the route (required)
///   --pace=MM:SS    ghost pace per km (default: the original run's pace, needs timestamps)
///   --elevation     with --pace: ghost slows uphill, speeds up downhill (same average)
///   --seconds=N     only render the first N seconds (default: the whole route)
///   --out=FILE      output mp3 (default dummy_run.mp3)
///   --no-breathing  footsteps only
///   --no-muffle     turn off the low-pass "behind" cue, to compare
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ghost_runner/run_math.dart';

import 'ghost_audio.dart';

Future<void> main(List<String> argv) async {
  try {
    await _render(argv);
  } on ArgumentError catch (e) {
    stderr.writeln(
      '${e.message} (see the options at the top of tool/dummy_run.dart)',
    );
    exitCode = 64;
  }
}

Future<void> _render(List<String> argv) async {
  final args = parseArgs(argv);
  final gpx = args['gpx'];
  if (gpx == null || !File(gpx).existsSync()) {
    throw ArgumentError('--gpx must be an existing GPX file, got "$gpx"');
  }
  final pace = args['pace'] ?? '';
  if (!isValidPace(pace)) {
    throw ArgumentError('--pace must be mm:ss, got "$pace"');
  }
  final secondsArg = args['seconds'];
  final seconds = secondsArg == null ? null : double.tryParse(secondsArg);
  if (secondsArg != null && (seconds == null || seconds <= 0)) {
    throw ArgumentError('--seconds must be a positive number, got "$secondsArg"');
  }
  final out = args['out'] ?? 'dummy_run.mp3';

  final route = await _loadRoute(
    gpx,
    pace.isEmpty ? '00:00' : pace,
    elevation: args.containsKey('elevation'),
  );
  final ticks = seconds == null
      ? route.length
      : min(route.length, (seconds * 1000 / tick.inMilliseconds).ceil());

  // Same per-tick steps as _onTick and _simulateRunner in main.dart.
  final along = distanceAlong(route);
  final tracker = WaypointTracker(waypoints(route, along));
  final random = Random();
  var side = random.nextBool() ? 1 : -1;
  double? prev;
  final gaps = <(double, int)>[];
  for (var i = 0; i < ticks; i++) {
    final elapsed = tick * i;
    final p = route[dummyRunnerTick(elapsed.inSeconds, tick, route.length)];
    tracker.update(p[1], p[0]);
    final raw = along[i] - tracker.metres;
    final gap = prev == null ? raw : prev + (raw - prev) * 0.05;
    if (gap.abs() >= 20 && (prev ?? 0).abs() < 20) {
      side = random.nextBool() ? 1 : -1;
    }
    prev = gap;
    gaps.add((gap, side));
  }

  final sounds = await renderGhost(
    samples: ticks * tickSamples,
    at: (sample) => gaps[sample ~/ tickSamples], // the app updates once a tick
    out: out,
    breathing: args['no-breathing'] == null,
    muffle: args['no-muffle'] == null,
  );
  final maxGap = gaps.map((g) => g.$1.abs()).reduce(max);
  // ignore: avoid_print
  print(
    'Wrote $out: ${(ticks * tick.inMilliseconds / 1000).toStringAsFixed(1)}s '
    'of ${along.last.round()}m route, '
    'gap up to ${maxGap.round()}m, $sounds overtake sound(s)',
  );
}

/// The ghost's route, one `[lon, lat]` point per tick, from process_route.js.
Future<List<List<double>>> _loadRoute(
  String gpx,
  String pace, {
  bool elevation = false,
}) async {
  final script = Platform.script
      .resolve('../../../back-end/process_route.js')
      .toFilePath();
  final r = await Process.run('node', [
    '-e',
    'const [, script, gpx, pace, elevation] = process.argv;'
        'try { const r = require(script).getRoute(gpx, pace, elevation === "true");'
        ' if (r.noElevation) console.error("No elevation data in this GPX, running flat");'
        ' process.stdout.write(JSON.stringify(r.route)); }'
        'catch (e) { console.error(e.message); process.exit(1); }',
    script,
    gpx,
    pace,
    '$elevation',
  ]);
  if (r.exitCode != 0) {
    throw ArgumentError('Could not build the route: ${'${r.stderr}'.trim()}');
  }
  return toPoints(jsonDecode(r.stdout as String) as List);
}
