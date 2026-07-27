import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SoLoud.instance.init(
    sampleRate: 44100,
    bufferSize: 2048,
    channels: Channels.stereo,
  );
  // final startupSound = await SoLoud.instance.loadAsset('assets/audio/footsteps.mp3');
  // final handle = SoLoud.instance.play(startupSound);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});
  Timer? _timer;
  SoundHandle? _ghostHandle;
  List<dynamic>? route;

  void _pickFile() async {
    final String pace = _textController.text.isEmpty
        ? '00:00'
        : _textController.text;
    final FilePickerResult? result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return;

    final PlatformFile file = result.files.first;

    await _uploadGpxFile(file, pace);
  }

  Future<void> _uploadGpxFile(PlatformFile file, pace) async {
    final uri = Uri.parse('http://localhost:3000/api/runs/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['pace'] = pace; //placeholder pace

    if (kIsWeb) {
      // Web
      request.files.add(
        http.MultipartFile.fromBytes(
          'gpxFile',
          file.bytes!,
          filename: file.name,
        ),
      );
    } else {
      // Mobile/desktop
      request.files.add(
        await http.MultipartFile.fromPath('gpxFile', file.path!),
      );
    }

    try {
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final rawRoute = decoded['route'] as List;

        route = rawRoute
            .map<List<double>>(
              (point) =>
                  (point as List).map((e) => (e as num).toDouble()).toList(),
            )
            .toList();
      } else {
        print('Upload failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('Error uploading file: $e');
    }
  }

  // Function from https://pub.dev/packages/geolocator
  Future<List<double>> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }
    Position position = await Geolocator.getCurrentPosition();
    List<double> positionList = [position.longitude, position.latitude];

    return positionList;
  }

  // TODO: Implement run cycle logic
  void _startRun() async {
    if (route == Null) {
      print("No route uploaded");
      return;
    }
    List<double> runnerPosition = await _determinePosition();
    List<double> difference = displacement(
      originLat: runnerPosition[1],
      originLon: runnerPosition[0],
      targetLat: route![0][1],
      targetLon: route![0][0],
    );
    final steps = await SoLoud.instance.loadAsset(
      'assets/audio/footsteps_mono.mp3',
    );
    _ghostHandle = SoLoud.instance.play3d(
      steps,
      difference[0],
      0,
      difference[1],
      looping: true,
    );
    final startTime = DateTime.now();
    int previousSecond = -1;
    int ghostInterval = 1;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      List<double> ghostPosition = route![ghostInterval];
      ghostInterval++;
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      final currentSecond = elapsedMs ~/ 1000;
      if (currentSecond != previousSecond) {
        previousSecond = currentSecond;
        // Update both runner position
        runnerPosition = await _determinePosition();
      }
      difference = displacement(
        originLat: runnerPosition[1],
        originLon: runnerPosition[0],
        targetLat: ghostPosition[1],
        targetLon: ghostPosition[0],
      );
      SoLoud.instance.set3dSourcePosition(
        _ghostHandle!,
        difference[0],
        0,
        difference[1],
      );
      double volume = getVolume(difference);
      SoLoud.instance.setVolume(_ghostHandle!, volume);
    });
  }

  List<double> displacement({
    required double originLat,
    required double originLon,
    required double targetLat,
    required double targetLon,
  }) {
    const double earthRadius = 6371000;

    final double lat1Rad = originLat * pi / 180;
    final double lat2Rad = targetLat * pi / 180;
    final double deltaLatRad = (targetLat - originLat) * pi / 180;
    final double deltaLonRad = (targetLon - originLon) * pi / 180;

    final double meanLat = (lat1Rad + lat2Rad) / 2;
    final double x = deltaLonRad * cos(meanLat) * earthRadius;
    final double z = deltaLatRad * earthRadius;

    return [x, z];
  }

  double getVolume(List<double> difference) {
    double distance = sqrt(
      difference[0] * difference[0] + difference[1] * difference[1],
    );
    double clampedDistance = distance.clamp(2.0, 50.0);
    double normalizedDistance = (clampedDistance - 2.0) / (50.0 - 2.0);
    double volume = 1 - normalizedDistance;
    return volume;
  }

  final TextEditingController _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color.fromARGB(255, 255, 50, 50),
          title: const Center(child: Text('Ghost Runner')),
        ),
        body: Column(
          children: [
            Container(
              color: const Color.fromARGB(255, 230, 40, 40),
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MaterialButton(
                    onPressed: () {
                      _pickFile();
                    },
                    child: Text(
                      'Upload Run',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        labelText: 'Enter your pace (optional)',
                        hintText: '05:00',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Main body
            Expanded(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32.0),
                      child: ElevatedButton(
                        onPressed: () {
                          _startRun();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          disabledBackgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          minimumSize: const Size(120, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          'GO',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
