/// Renders what the app sounds like during an overtake: the gap along the route
/// (metres the ghost is ahead) changes steadily from --from to --to.
/// Uses the app's own placement, volume, muffle and overtake logic (run_math.dart),
/// plays the overtake sound when the app would, and copies SoLoud's stereo
/// panning. Needs ffmpeg on PATH.
///
///   dart run tool/overtake.dart --speed=4 --out=overtake.mp3
///
/// Options (all optional):
///   --speed=M/S     how fast the gap closes, metres/second (default 3.33, i.e. 5:00/km)
///   --pace=MM:SS    the same as a pace per km instead of --speed
///   --side=left|right  which ear the ghost passes (default random, like the app)
///   --from=M        gap at the start, negative = ghost behind (default -100)
///   --to=M          gap at the end (default 100); --from=100 --to=-100 is the
///                   runner overtaking the ghost
///   --out=FILE      output mp3 (default overtake.mp3)
///   --no-breathing  footsteps only
///   --no-muffle     turn off the low-pass "behind" cue, to compare
library;

import 'dart:io';
import 'dart:math';

import 'package:ghost_runner/run_math.dart';

import 'ghost_audio.dart';

Future<void> main(List<String> argv) async {
  try {
    await _render(argv);
  } on ArgumentError catch (e) {
    stderr.writeln(
      '${e.message} (see the options at the top of tool/overtake.dart)',
    );
    exitCode = 64;
  }
}

Future<void> _render(List<String> argv) async {
  final args = parseArgs(argv);
  double num(String key, double fallback) {
    final v = args[key];
    if (v == null) return fallback;
    return double.tryParse(v) ??
        (throw ArgumentError('--$key must be a number, got "$v"'));
  }

  var speed = num('speed', 1000 / 300);
  final pace = args['pace'];
  if (pace != null) {
    if (pace.isEmpty || !isValidPace(pace)) {
      throw ArgumentError('--pace must be mm:ss, got "$pace"');
    }
    final [m, s] = pace.split(':').map(int.parse).toList();
    speed = 1000 / (m * 60 + s);
  }
  if (speed <= 0) throw ArgumentError('speed must be positive');
  final from = num('from', -100), to = num('to', 100);
  if (from == to) throw ArgumentError('--from and --to must differ');
  final sideArg = args['side'] ?? (Random().nextBool() ? 'right' : 'left');
  if (sideArg != 'left' && sideArg != 'right') {
    throw ArgumentError('--side must be left or right, got "$sideArg"');
  }
  final side = sideArg == 'right' ? 1 : -1;
  final out = args['out'] ?? 'overtake.mp3';
  final breathing = args['no-breathing'] == null,
      muffle = args['no-muffle'] == null;

  final n = ((to - from).abs() / speed * rate).round();
  final velocity = (to - from).sign * speed;
  final sounds = await renderGhost(
    samples: n,
    at: (i) => (from + velocity * i / rate, side),
    out: out,
    breathing: breathing,
    muffle: muffle,
  );
  // ignore: avoid_print
  print(
    'Wrote $out: ${(n / rate).toStringAsFixed(1)}s, gap ${from}m to ${to}m at '
    '${speed.toStringAsFixed(2)} m/s, passing on the $sideArg, '
    '$sounds overtake sound(s)',
  );
}
