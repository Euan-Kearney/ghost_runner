import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;

import 'run_math.dart';
import 'run_page.dart';

/// Override with `flutter run --dart-define=API_URL=http://10.0.2.2:3000`
/// (Android emulator) or your computer's LAN IP (real phone).
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:3000',
);
const tick = Duration(
  milliseconds: 50,
); // must match TICK_SECONDS on the server

const neon = Color(0xFF39FF14);
const _surface = Color(0xFF0E0E0E);
const _outline = Color(0xFF262626);

/// Bold neon-green text.
TextStyle neonText(double size) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w900,
  color: neon,
  height: 1.1,
);

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
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _outline),
    );
    return MaterialApp(
      title: 'Ghost Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: neon,
          onPrimary: Colors.black,
          secondary: neon,
          onSecondary: Colors.black,
          surface: _surface,
          onSurface: Colors.white,
          outline: _outline,
          error: Color(0xFFFF4D6D),
        ),
        cardTheme: CardThemeData(
          color: _surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: _outline),
          ),
        ),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: _surface,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: neon, width: 2),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// Big round button (GO / STOP / DONE).
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Theme.of(context).colorScheme.error : neon;
    return SizedBox(
      width: 120,
      height: 120,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: color,
          foregroundColor: Colors.black,
          disabledBackgroundColor: _outline,
          textStyle: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        // Shrink long labels (RESUME) to fit on one line instead of wrapping.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
      ),
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

  PlatformFile? _file;
  List<List<double>>? _route; // ghost positions, one per 50ms tick
  String? _loadedPace; // pace the current route was built with
  bool _loading = false;
  String? _error;
  int _requestId = 0; // only the latest upload may update the state

  String get _pace => _paceController.text.trim();

  @override
  void dispose() {
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
    final id = ++_requestId;
    final pace = _pace;
    setState(() {
      _loading = true;
      _error = null;
      _route = null;
    });

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiUrl/api/runs/upload'),
    );
    request.fields['pace'] = pace.isEmpty ? '00:00' : pace;
    request.files.add(
      file.bytes != null
          ? http.MultipartFile.fromBytes(
              'gpxFile',
              file.bytes!,
              filename: file.name,
            )
          : await http.MultipartFile.fromPath('gpxFile', file.path!),
    );

    String? error;
    List<List<double>>? route;
    try {
      final response = await http.Response.fromStream(await request.send());
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        route = toPoints(body['route'] as List);
      } else {
        error =
            body['error'] as String? ??
            'Upload failed (${response.statusCode})';
      }
    } catch (e) {
      error = "Couldn't reach the server at $apiUrl";
      debugPrint('Upload error: $e');
    }
    if (!mounted || id != _requestId) return;
    setState(() {
      _loading = false;
      _error = error;
      _route = route;
      if (route != null) _loadedPace = pace;
    });
  }

  Future<void> _go() async {
    // Pace changed since upload: rebuild the route first.
    if (_loadedPace != _pace) await _loadRoute();
    final route = _route;
    if (route == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunPage(route: route, dummy: _dummyRoute),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final paceValid = isValidPace(_pace);
    final canStart = _file != null && paceValid && !_loading;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          // Fill the window when it's tall enough, scroll when it isn't (small desktop windows).
          builder: (context, viewport) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  minHeight: max(0, viewport.maxHeight - 40),
                ),
                child: Column(
                  // Form at the top, GO at the bottom.
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        const Text(
                          '👻',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 56),
                        ),
                        Text(
                          'GHOST RUNNER',
                          textAlign: TextAlign.center,
                          style: neonText(34).copyWith(letterSpacing: 4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Race the ghost of a run',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              16,
                              8,
                              12,
                              8,
                            ),
                            leading: const Icon(Icons.route, color: neon),
                            title: Text(
                              _file?.name ?? 'No route selected',
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: switch (_routeSummary()) {
                              final s? => Text(s),
                              null => null,
                            },
                            trailing: _loading
                                ? const SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: _pickFile,
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('GPX'),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _paceController,
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) {
                            setState(() {});
                            if (_loadedPace != _pace) _loadRoute();
                          },
                          decoration: InputDecoration(
                            labelText: 'Ghost pace (min/km)',
                            hintText: '05:30',
                            prefixIcon: const Icon(Icons.speed),
                            helperText: 'Leave blank to match the original run',
                            errorText: paceValid
                                ? null
                                : 'Use mm:ss, e.g. 05:30',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: SwitchListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            secondary: const Icon(Icons.smart_toy_outlined),
                            title: const Text('Dummy run'),
                            subtitle: const Text(
                              'Simulate yourself on the route, no GPS needed',
                            ),
                            value: _dummyRoute,
                            onChanged: (v) => setState(() => _dummyRoute = v),
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 32, bottom: 8),
                      child: Center(
                        child: NeonButton(
                          label: 'GO',
                          onPressed: canStart ? _go : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _routeSummary() {
    final route = _route;
    if (_loading) return 'Processing…';
    if (route == null) return 'Upload a GPX file to race its ghost';
    if (_loadedPace != _pace) return null; // pace is invalid (valid edits reload)
    return 'Ghost finishes in ${formatDuration(tick * route.length)}';
  }
}

String formatDuration(Duration d) {
  final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}
