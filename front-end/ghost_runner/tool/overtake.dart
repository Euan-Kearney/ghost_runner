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
import 'dart:typed_data';

import 'package:ghost_runner/run_math.dart';

const _rate = 44100;
const _tickSamples =
    _rate * 50 ~/ 1000; // the app updates audio every 50ms tick

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
  final args = {
    for (final a in argv)
      if (a.startsWith('--'))
        a.substring(2).split('=').first: a.contains('=')
            ? a.split('=')[1]
            : 'true',
  };
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

  final assets = Platform.script.resolve('../assets/audio/');
  final steps = await _decode(assets.resolve('Footsteps.mp3'));
  final breath = await _decode(assets.resolve('breathing.wav'));
  final ghostPasses = await _decode(
    assets.resolve('ghost_overtake.mp3'),
    channels: 2,
  );
  final runnerPasses = await _decode(
    assets.resolve('runner_overtake.mp3'),
    channels: 2,
  );

  final n = ((to - from).abs() / speed * _rate).round();
  final velocity = (to - from).sign * speed;
  double gap(int sample) => from + velocity * sample / _rate;
  final stereo = Float32List(n * 2);
  final filter = _LowPass();
  final overtakes = OvertakeDetector();
  final sounds = <(int, Float32List)>[]; // (start sample, stereo sfx)
  for (var start = 0; start < n; start += _tickSamples) {
    final tickOffset = ghostOffset(gap(start), side);
    filter.setCutoff(muffle ? lowPassCutoff(tickOffset) : 16000);
    final now = Duration(microseconds: start * 1000000 ~/ _rate);
    switch (overtakes.update(gap(start), now)) {
      case true:
        sounds.add((start, ghostPasses));
      case false:
        sounds.add((start, runnerPasses));
      case null:
    }
    for (var i = start; i < min(start + _tickSamples, n); i++) {
      final offset = ghostOffset(gap(i), side); // [right, forward]
      var x = steps[i % steps.length] * getVolume(offset);
      if (breathing) {
        x += breath[i % breath.length] * getVolume(offset, range: 40);
      }
      x *= behindGain(offset);
      x = filter.process(x);
      final (left, right) = _soloudPan(offset);
      stereo[2 * i] = (x * left).clamp(-1, 1);
      stereo[2 * i + 1] = (x * right).clamp(-1, 1);
    }
  }
  // Overtake sounds play unpositioned (SoLoud.play), straight over the top.
  for (final (start, sfx) in sounds) {
    for (var j = 0; j < sfx.length && 2 * start + j < stereo.length; j++) {
      stereo[2 * start + j] = (stereo[2 * start + j] + sfx[j]).clamp(-1, 1);
    }
  }

  final ffmpeg = await Process.start('ffmpeg', [
    '-y',
    '-loglevel',
    'error',
    '-f',
    'f32le',
    '-ar',
    '$_rate',
    '-ac',
    '2',
    '-i',
    '-',
    '-b:a', '192k', out, //
  ]);
  ffmpeg.stdin.add(stereo.buffer.asUint8List());
  await ffmpeg.stdin.close();
  stderr.addStream(ffmpeg.stderr);
  if (await ffmpeg.exitCode != 0) {
    throw StateError('ffmpeg failed to write $out');
  }
  // ignore: avoid_print
  print(
    'Wrote $out: ${(n / _rate).toStringAsFixed(1)}s, gap ${from}m to ${to}m at '
    '${speed.toStringAsFixed(2)} m/s, passing on the $sideArg, '
    '${sounds.length} overtake sound(s)',
  );
}

/// Decodes any audio file to 44.1kHz floats (interleaved if [channels] is 2).
// shortcut: spatialised sources are downmixed to mono like a point source.
Future<Float32List> _decode(Uri file, {int channels = 1}) async {
  final r = await Process.run('ffmpeg', [
    '-loglevel',
    'error',
    '-i',
    file.toFilePath(),
    '-f',
    'f32le',
    '-ac',
    '$channels',
    '-ar',
    '$_rate',
    '-',
  ], stdoutEncoding: null);
  if (r.exitCode != 0) {
    throw StateError('ffmpeg could not decode $file: ${r.stderr}');
  }
  return Uint8List.fromList(r.stdout as List<int>).buffer.asFloat32List();
}

/// SoLoud's stereo 3D pan (soloud_core_3d.cpp): each speaker's gain is
/// (dot(speaker, direction) + 1) / 2, with speakers at (±2, 0, 1) in listener space.
/// The app places the ghost at (right, 0, -forward) with the listener facing -z,
/// which in listener space is x = -right (x points left), z = forward.
(double, double) _soloudPan(List<double> offset) {
  final d = sqrt(offset[0] * offset[0] + offset[1] * offset[1]);
  if (d == 0) return (0.5, 0.5);
  final x = -offset[0] / d, z = offset[1] / d;
  double gain(double sx) => ((sx * x + z) / sqrt(5) + 1) / 2;
  return (gain(2), gain(-2));
}

/// RBJ biquad low-pass with Q 0.707, matching the resonance main.dart sets.
class _LowPass {
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  void setCutoff(double hz) {
    final w = 2 * pi * hz / _rate, c = cos(w), alpha = sin(w) / (2 * 0.707);
    final a0 = 1 + alpha;
    _b0 = (1 - c) / 2 / a0;
    _b1 = (1 - c) / a0;
    _b2 = _b0;
    _a1 = -2 * c / a0;
    _a2 = (1 - alpha) / a0;
  }

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}
