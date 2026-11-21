import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'run_math.dart';

/// Override with `flutter run --dart-define=API_URL=http://10.0.2.2:3000`
/// (Android emulator) or your computer's LAN IP (real phone).
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:3000',
);
const _tick = Duration(milliseconds: 50); // must match TICK_SECONDS on the server

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SoLoud.instance.init(
    sampleRate: 44100,
    bufferSize: 2048,
    channels: Channels.stereo,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF3232),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _paceController = TextEditingController();
  bool _dummyRoute = false;

  // Route
  PlatformFile? _file;
  List<List<double>>? _route; // ghost positions, one per 50ms tick
  List<List<double>>? _runnerRoute; // dummy runs only: runner positions, one per second
  String? _loadedSettings; // pace/dummy the current route was built with
  bool _loading = false;
  String? _error;

  // Run
  Timer? _timer;
  StreamSubscription<Position>? _gps;
  AudioSource? _footsteps;
  SoundHandle? _ghostHandle;
  double? _runnerLat, _runnerLon;
  double _heading = 0;
  List<double>? _offset; // [right, forward] metres from runner to ghost
  Duration _elapsed = Duration.zero;
  String? _finishedMessage;

  bool get _running => _timer != null;
  String get _pace => _paceController.text.trim();
  String get _settings => '$_pace|$_dummyRoute';

  @override
  void dispose() {
    _teardownRun();
    _paceController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null) return;
    _file = result.files.first;
    await _loadRoute();
  }

  /// Sends the GPX file to the server, which builds the ghost's route at the chosen pace.
  Future<void> _loadRoute() async {
    final file = _file;
    if (file == null || !isValidPace(_pace)) return;
    setState(() {
      _loading = true;
      _error = null;
      _route = null;
    });

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiUrl/api/runs/upload'),
    );
    request.fields['pace'] = _pace.isEmpty ? '00:00' : _pace;
    request.fields['dummyRoute'] = _dummyRoute.toString();
    request.files.add(
      file.bytes != null
          ? http.MultipartFile.fromBytes('gpxFile', file.bytes!, filename: file.name)
          : await http.MultipartFile.fromPath('gpxFile', file.path!),
    );

    String? error;
    try {
      final response = await http.Response.fromStream(await request.send());
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        _route = toPoints(body['route'] as List);
        _runnerRoute = body['runnerRoute'] == null
            ? null
            : toPoints(body['runnerRoute'] as List);
        _loadedSettings = _settings;
      } else {
        error = body['error'] as String? ?? 'Upload failed (${response.statusCode})';
      }
    } catch (e) {
      error = "Couldn't reach the server at $apiUrl";
      debugPrint('Upload error: $e');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  // Adapted from https://pub.dev/packages/geolocator
  Future<void> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Location services are disabled.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw 'Location permission is needed to hear the ghost.';
    }
  }

  Future<void> _startRun() async {
    // Pace or dummy mode changed since upload: rebuild the route first.
    if (_loadedSettings != _settings) await _loadRoute();
    final route = _route;
    if (route == null || _running) return;

    _runnerLat = _runnerLon = _offset = _finishedMessage = null;
    _heading = 0;
    try {
      if (!_dummyRoute) {
        await _ensureLocationPermission();
        _gps = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
        ).listen((p) {
          _runnerLat = p.latitude;
          _runnerLon = p.longitude;
          // GPS heading is direction of travel, which is noise when standing still.
          if (p.heading >= 0 && p.speed > 0.5) _heading = p.heading;
        });
      }
      _footsteps ??= await SoLoud.instance.loadAsset('assets/audio/Footsteps.mp3');
      _ghostHandle = SoLoud.instance.play3d(_footsteps!, 0, 0, 0, looping: true, volume: 0);
    } catch (e) {
      _teardownRun();
      setState(() => _error = '$e');
      return;
    }

    final start = DateTime.now();
    setState(() {
      _error = null;
      _elapsed = Duration.zero;
      // Index by elapsed time rather than counting ticks, so timer delays don't make the ghost lag.
      _timer = Timer.periodic(_tick, (_) => _onTick(DateTime.now().difference(start)));
    });
  }

  void _onTick(Duration elapsed) {
    final route = _route!;
    final i = elapsed.inMilliseconds ~/ _tick.inMilliseconds;
    if (i >= route.length) {
      _stopRun('The ghost has finished!');
      return;
    }
    if (_dummyRoute) _simulateRunner(elapsed);

    final lat = _runnerLat, lon = _runnerLon;
    List<double>? offset;
    if (lat != null && lon != null) {
      offset = displacement(
        originLat: lat,
        originLon: lon,
        targetLat: route[i][1],
        targetLon: route[i][0],
        heading: _heading,
      );
      // SoLoud's listener faces -z, so "forward" is negative z.
      SoLoud.instance.set3dSourcePosition(_ghostHandle!, offset[0], 0, -offset[1]);
      SoLoud.instance.setVolume(_ghostHandle!, getVolume(offset));
    }
    setState(() {
      _elapsed = elapsed;
      _offset = offset;
    });
  }

  /// Dummy run: replay the original run (1 point per second, like a GPS fix).
  void _simulateRunner(Duration elapsed) {
    final runner = _runnerRoute!;
    final s = min(elapsed.inSeconds, runner.length - 1);
    _runnerLon = runner[s][0];
    _runnerLat = runner[s][1];
    if (s + 1 < runner.length && runner[s] != runner[s + 1]) {
      _heading = bearing(runner[s][1], runner[s][0], runner[s + 1][1], runner[s + 1][0]);
    }
  }

  void _stopRun([String message = 'Run stopped']) {
    _teardownRun();
    setState(() => _finishedMessage = message);
  }

  void _teardownRun() {
    _timer?.cancel();
    _timer = null;
    _gps?.cancel();
    _gps = null;
    if (_ghostHandle != null) SoLoud.instance.stop(_ghostHandle!);
    _ghostHandle = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final paceValid = isValidPace(_pace);
    final canStart = _file != null && paceValid && !_loading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghost Runner'),
        centerTitle: true,
        backgroundColor: colors.primaryContainer,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.route),
                  title: Text(_file?.name ?? 'No route selected'),
                  subtitle: Text(_routeSummary()),
                  trailing: _loading
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonalIcon(
                          onPressed: _running ? null : _pickFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload'),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _paceController,
                enabled: !_running,
                keyboardType: TextInputType.datetime,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Ghost pace (min/km)',
                  hintText: '05:30',
                  prefixIcon: const Icon(Icons.speed),
                  border: const OutlineInputBorder(),
                  helperText: 'Leave blank to match the original run',
                  errorText: paceValid ? null : 'Use mm:ss, e.g. 05:30',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Dummy run'),
                subtitle: const Text('Simulate yourself by replaying the route, no GPS needed'),
                value: _dummyRoute,
                onChanged: _running ? null : (v) => setState(() => _dummyRoute = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
              Expanded(child: Center(child: _runPanel(colors))),
              Center(
                child: SizedBox.square(
                  dimension: 120,
                  child: FilledButton(
                    onPressed: _running ? () => _stopRun() : (canStart ? _startRun : null),
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: _running ? colors.error : Colors.green,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    child: Text(_running ? 'STOP' : 'GO'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _routeSummary() {
    final route = _route;
    if (_loading) return 'Processing…';
    if (route == null) return 'Upload a GPX file to race its ghost';
    return 'Ghost finishes in ${_formatDuration(_tick * route.length)}';
  }

  Widget _runPanel(ColorScheme colors) {
    final textTheme = Theme.of(context).textTheme;
    if (!_running) {
      return Text(
        _finishedMessage ?? (_route == null ? '' : 'Ready when you are'),
        style: textTheme.titleLarge,
      );
    }
    final offset = _offset;
    if (offset == null) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Waiting for GPS…')],
      );
    }
    final metres = sqrt(offset[0] * offset[0] + offset[1] * offset[1]).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Arrow points to the ghost, relative to the way you're running.
        Transform.rotate(
          angle: atan2(offset[0], offset[1]),
          child: Icon(Icons.navigation, size: 96, color: colors.primary),
        ),
        const SizedBox(height: 8),
        Text(
          'Ghost $metres m ${offset[1] >= 0 ? 'ahead' : 'behind'}',
          style: textTheme.headlineSmall,
        ),
        Text(_formatDuration(_elapsed), style: textTheme.displayMedium),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}
