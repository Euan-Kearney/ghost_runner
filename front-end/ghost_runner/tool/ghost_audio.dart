/// Shared by tool/overtake.dart and tool/dummy_run.dart: renders the ghost as the
/// app plays it, using the app's placement, volume, muffle and overtake logic
/// (run_math.dart), and copies SoLoud's stereo panning. Needs ffmpeg on PATH.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ghost_runner/run_math.dart';

const rate = 44100;
const tick = Duration(
  milliseconds: 50,
); // the app updates audio every 50ms tick
const tickSamples = rate * 50 ~/ 1000;

/// `--key=value` / `--flag` command-line options.
Map<String, String> parseArgs(List<String> argv) => {
  for (final a in argv)
    if (a.startsWith('--'))
      a.substring(2).split('=').first: a.contains('=')
          ? a.substring(a.indexOf('=') + 1)
          : 'true',
};

/// Mixes [samples] samples of the ghost to [out] (mp3). [at] gives the gap (metres
/// the ghost is ahead along the route) and side (1 right, -1 left) at a sample.
/// Returns how many overtake sounds played.
Future<int> renderGhost({
  required int samples,
  required (double, int) Function(int sample) at,
  required String out,
  bool breathing = true,
  bool muffle = true,
}) async {
  final assets = Platform.script.resolve('../assets/audio/');
  final steps = await _decode(assets.resolve('Footsteps.mp3'));
  final breath = await _decode(assets.resolve('breathing.wav'));
  final heart = await _decode(assets.resolve('heartbeat.wav'));
  final ghostPasses = await _decode(
    assets.resolve('ghost_overtake.mp3'),
    channels: 2,
  );
  final runnerPasses = await _decode(
    assets.resolve('runner_overtake.mp3'),
    channels: 2,
  );

  final n = samples;
  final stereo = Float32List(n * 2);
  final filter = _LowPass();
  final overtakes = OvertakeDetector();
  final sounds = <(int, Float32List)>[]; // (start sample, stereo sfx)
  for (var start = 0; start < n; start += tickSamples) {
    final (tickGap, tickSide) = at(start);
    filter.setCutoff(
      muffle ? lowPassCutoff(ghostOffset(tickGap, tickSide)) : 16000,
    );
    final now = Duration(microseconds: start * 1000000 ~/ rate);
    switch (overtakes.update(tickGap, now)) {
      case true:
        sounds.add((start, ghostPasses));
      case false:
        sounds.add((start, runnerPasses));
      case null:
    }
    for (var i = start; i < min(start + tickSamples, n); i++) {
      final (gap, side) = at(i);
      final offset = ghostOffset(gap, side); // [right, forward]
      var x =
          steps[i % steps.length] * getVolume(offset, range: footstepsRange);
      if (breathing) {
        x +=
            breath[i % breath.length] *
            getVolume(offset, range: breathingRange);
      }
      x *= behindGain(offset);
      x = filter.process(x);
      final (left, right) = _soloudPan(offset);
      // The runner's heartbeat: unpositioned and unfiltered, like SoLoud.play.
      final h = heart[i % heart.length] * heartbeatVolume(gap);
      stereo[2 * i] = (x * left + h).clamp(-1, 1);
      stereo[2 * i + 1] = (x * right + h).clamp(-1, 1);
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
    '$rate',
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
  return sounds.length;
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
    '$rate',
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
    final w = 2 * pi * hz / rate, c = cos(w), alpha = sin(w) / (2 * 0.707);
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
