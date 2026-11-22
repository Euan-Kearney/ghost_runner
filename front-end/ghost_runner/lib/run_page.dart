import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'main.dart';
import 'run_math.dart';

/// The run itself: a 5s countdown, then the ghost's sound and both runners on a map.
class RunPage extends StatefulWidget {
  const RunPage({super.key, required this.route, required this.dummy});

  final List<List<double>> route; // ghost positions, one per 50ms tick
  final bool dummy;

  @override
  State<RunPage> createState() => _RunPageState();
}

class _RunPageState extends State<RunPage> {
  late final List<double> _ghostAlong = distanceAlong(widget.route);
  late final List<List<double>> _waypoints = waypoints(
    widget.route,
    _ghostAlong,
  );
  late final _tracker = WaypointTracker(_waypoints);
  final _overtakes = OvertakeDetector();
  final _random = Random();
  final _mapController = MapController();
  final _runnerGlide = Glide();
  double _runnerShown =
      0; // runner's metres along the route as drawn, moving every tick

  Timer? _timer;
  StreamSubscription<Position>? _gps;
  AudioSource? _footsteps, _breathing, _ghostOvertakes, _runnerOvertakes;
  SoundHandle? _ghostHandle, _breathHandle;
  double? _runnerLat, _runnerLon;
  double? _gap; // metres the ghost is ahead along the route (smoothed)
  late int _side = _random.nextBool()
      ? 1
      : -1; // ear the ghost passes: 1 right, -1 left
  int? _countdown; // seconds left before the start, null once running
  Duration _elapsed = Duration.zero;
  int _tickIndex = 0;
  String? _error, _finished;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _teardown();
    _mapController.dispose();
    for (final source in [
      _footsteps,
      _breathing,
      _ghostOvertakes,
      _runnerOvertakes,
    ]) {
      if (source != null) SoLoud.instance.disposeSource(source);
    }
    super.dispose();
  }

  /// Loads sounds and starts GPS before the countdown, so the fix is warm at GO.
  Future<void> _prepare() async {
    try {
      if (!widget.dummy) {
        await _ensureLocationPermission();
        _gps =
            Geolocator.getPositionStream(
              locationSettings: _locationSettings(),
            ).listen((p) {
              _runnerLat = p.latitude;
              _runnerLon = p.longitude;
            });
      }
      _footsteps = await _loadWithFilter('assets/audio/Footsteps.mp3');
      _breathing = await _loadWithFilter('assets/audio/breathing.wav');
      _ghostOvertakes = await SoLoud.instance.loadAsset(
        'assets/audio/ghost_overtake.mp3',
      );
      _runnerOvertakes = await SoLoud.instance.loadAsset(
        'assets/audio/runner_overtake.mp3',
      );
    } catch (e) {
      _teardown();
      if (mounted) setState(() => _error = '$e');
      return;
    }
    if (!mounted || _finished != null) return; // left or stopped while loading
    setState(() => _countdown = 5);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown! > 1) return setState(() => _countdown = _countdown! - 1);
      t.cancel();
      _start();
    });
  }

  /// iOS needs to be told to keep GPS running with the screen locked
  /// (pairs with UIBackgroundModes `location` in ios/Runner/Info.plist).
  LocationSettings _locationSettings() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? AppleSettings(
          accuracy: LocationAccuracy.best,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        )
      : const LocationSettings(accuracy: LocationAccuracy.best);

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

  /// Loads a looping ghost sound with a low-pass filter, used to muffle it when the ghost is behind.
  Future<AudioSource> _loadWithFilter(String asset) async {
    final source = await SoLoud.instance.loadAsset(asset);
    // shortcut: per-sound filters aren't supported on web, so no front/back muffling there.
    if (!kIsWeb) source.filters.biquadFilter.activate();
    return source;
  }

  void _start() {
    _ghostHandle = SoLoud.instance.play3d(
      _footsteps!,
      0,
      0,
      0,
      looping: true,
      volume: 0,
    );
    _breathHandle = SoLoud.instance.play3d(
      _breathing!,
      0,
      0,
      0,
      looping: true,
      volume: 0,
    );
    if (!kIsWeb) {
      // Default resonance (0.1) dulls everything; 0.707 is a flat low-pass.
      _footsteps!.filters.biquadFilter
              .resonance(soundHandle: _ghostHandle)
              .value =
          0.707;
      _breathing!.filters.biquadFilter
              .resonance(soundHandle: _breathHandle)
              .value =
          0.707;
    }
    final start = DateTime.now();
    setState(() => _countdown = null);
    // Index by elapsed time rather than counting ticks, so timer delays don't make the ghost lag.
    _timer = Timer.periodic(
      tick,
      (_) => _onTick(DateTime.now().difference(start)),
    );
  }

  void _onTick(Duration elapsed) {
    final route = widget.route;
    final i = elapsed.inMilliseconds ~/ tick.inMilliseconds;
    if (i >= route.length) return _stop('The ghost has finished!');
    if (widget.dummy) _simulateRunner(elapsed);

    final lat = _runnerLat, lon = _runnerLon;
    if (lat != null && lon != null) {
      _tracker.update(lat, lon);
      _runnerShown = _runnerGlide.update(_tracker.metres, elapsed);
      if (_tracker.reached >= 0) _follow();
      final raw = _ghostAlong[i] - _tracker.metres;
      final prev = _gap;
      // Ease towards the new gap (~1s) so 1Hz GPS fixes don't make the sound jump.
      final gap = prev == null ? raw : prev + (raw - prev) * 0.05;
      // Pick the side of the next overtake while the ghost is too far off for the switch to be heard.
      if (gap.abs() >= 20 && (prev ?? 0).abs() < 20) {
        _side = _random.nextBool() ? 1 : -1;
      }
      _gap = gap;
      switch (_overtakes.update(gap, elapsed)) {
        case true:
          SoLoud.instance.play(_ghostOvertakes!);
        case false:
          SoLoud.instance.play(_runnerOvertakes!);
        case null:
      }
      final offset = ghostOffset(gap, _side);
      final cutoff = lowPassCutoff(offset), gain = behindGain(offset);
      // Footsteps carry 100m; breathing only kicks in within 40m.
      for (final (source, handle, range) in [
        (_footsteps!, _ghostHandle!, 100.0),
        (_breathing!, _breathHandle!, 40.0),
      ]) {
        // SoLoud's listener faces -z, so "forward" is negative z.
        SoLoud.instance.set3dSourcePosition(handle, offset[0], 0, -offset[1]);
        SoLoud.instance.setVolume(
          handle,
          getVolume(offset, range: range) * gain,
        );
        if (!kIsWeb) {
          source.filters.biquadFilter.frequency(soundHandle: handle).value =
              cutoff;
        }
      }
    }
    setState(() {
      _elapsed = elapsed;
      _tickIndex = i;
    });
  }

  /// Keeps the runner in view, above the stats panel, at whatever zoom the user pinched to.
  void _follow() => _mapController.move(
    _latLng(pointAt(_waypoints, _runnerShown)),
    _mapController.camera.zoom,
    offset: const Offset(0, -130), // panel covers the bottom ~360px
  );

  /// Dummy run: a fake runner on the ghost's route, swapping places with it every 75s.
  void _simulateRunner(Duration elapsed) {
    final route = widget.route;
    final p = route[dummyRunnerTick(elapsed.inSeconds, tick, route.length)];
    _runnerLon = p[0];
    _runnerLat = p[1];
  }

  void _stop([String message = 'Run stopped']) {
    _teardown();
    setState(() => _finished = message);
  }

  void _teardown() {
    _timer?.cancel();
    _timer = null;
    _gps?.cancel();
    _gps = null;
    for (final handle in [_ghostHandle, _breathHandle]) {
      if (handle != null) SoLoud.instance.stop(handle);
    }
    _ghostHandle = _breathHandle = null;
  }

  LatLng _latLng(List<double> p) => LatLng(p[1], p[0]);

  @override
  Widget build(BuildContext context) {
    final countdown = _countdown;
    final over = _finished != null || _error != null;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _map()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _clock()),
                  const Spacer(),
                  _panel(),
                  const SizedBox(height: 16),
                  Center(
                    child: NeonButton(
                      label: over ? 'DONE' : 'STOP',
                      danger: !over,
                      onPressed: over
                          ? () => Navigator.pop(context)
                          : () => _stop(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Esri, HERE, Garmin, © OpenStreetMap contributors',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
          if (countdown != null || (_elapsed.inSeconds < 1 && !over))
            Positioned.fill(child: _countdownOverlay(countdown)),
        ],
      ),
    );
  }

  Widget _map() {
    final line = [for (final p in _waypoints) _latLng(p)];
    final ghost = pointAt(_waypoints, _ghostAlong[_tickIndex]);
    final runner = _tracker.reached < 0
        ? null
        : pointAt(_waypoints, _runnerShown);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        backgroundColor: Colors.black,
        // Start of the route until the runner reaches it, then _follow takes over.
        initialCenter: line.first,
        initialZoom: 17,
      ),
      children: [
        // Esri Dark Gray Canvas: plain streets, no points of interest, plus a layer of just street names.
        // shortcut: keyless public tiles, fine for dev/field testing; Esri's terms need an ArcGIS account
        // (or another keyed provider) before release.
        for (final layer in ['Base', 'Reference'])
          TileLayer(
            urlTemplate:
                'https://services.arcgisonline.com/arcgis/rest/services/Canvas/World_Dark_Gray_$layer/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.example.ghost_runner',
            maxNativeZoom:
                16, // deeper zooms return "no data" tiles; upscale z16 instead
          ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: line,
              strokeWidth: 4,
              color: neon,
              borderStrokeWidth: 6,
              borderColor: neon.withValues(alpha: 0.25),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            _marker(ghost, '👻', 'Ghost'),
            if (runner != null) _marker(runner, '👟', 'You'),
          ],
        ),
      ],
    );
  }

  Marker _marker(List<double> p, String emoji, String label) => Marker(
    point: _latLng(p),
    width: 44,
    height: 44,
    child: Semantics(
      label: label,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          border: Border.all(color: neon, width: 2),
          boxShadow: [
            BoxShadow(color: neon.withValues(alpha: 0.6), blurRadius: 12),
          ],
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    ),
  );

  Widget _clock() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: neon.withValues(alpha: 0.4)),
    ),
    child: Text(
      formatDuration(_elapsed),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );

  Widget _panel() {
    final textTheme = Theme.of(context).textTheme;
    final gap = _gap;
    final String big, small;
    if (_error != null) {
      big = '!';
      small = _error!;
    } else if (gap == null) {
      big = '--';
      small = _countdown != null
          ? 'Get ready'
          : (widget.dummy ? 'Starting…' : 'Waiting for GPS…');
    } else {
      big = '${gap.abs().round()} m';
      small = gap >= 0 ? 'GHOST AHEAD' : 'GHOST BEHIND';
    }
    final ahead = (gap ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: neon.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_finished != null) Text(_finished!, style: textTheme.titleMedium),
          Text(
            big,
            style: neonText(64).copyWith(
              color: ahead ? neon : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            small,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              letterSpacing: 3,
              color: _error != null
                  ? Theme.of(context).colorScheme.error
                  : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdownOverlay(int? countdown) => IgnorePointer(
    ignoring: countdown == null, // let the map through once GO! shows
    child: ColoredBox(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: countdown == null && _error == null && _timer == null
            ? const CircularProgressIndicator() // loading sounds / GPS
            : Text(countdown?.toString() ?? 'GO!', style: neonText(140)),
      ),
    ),
  );
}
