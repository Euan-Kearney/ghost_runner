import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http; 
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  void _pickFile() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return;

    final PlatformFile file = result.files.first;
    print('File Name: ${file.name}');
    print('File Size: ${file.size} bytes');
    print('File Path: ${file.path}');

    await _uploadGpxFile(file);
}

Future<void> _uploadGpxFile(PlatformFile file) async {
  final uri = Uri.parse('http://localhost:3000/api/runs/upload');
  final request = http.MultipartRequest('POST', uri);
  request.fields['pace'] = "00:00"; //placeholder pace

  if (kIsWeb) {
    // Web: no filesystem access, so we need the raw bytes instead of a path.
    request.files.add(
      http.MultipartFile.fromBytes('gpxFile', file.bytes!, filename: file.name),
    );
  } else {
    // Mobile/desktop: file.path is available, stream straight from disk.
    request.files.add(
      await http.MultipartFile.fromPath('gpxFile', file.path!),
    );
  }

  try {
    final streamed = await request.send();
    //response contains the smoothed route json
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      print('Route received: ${response.body}');
      // TODO: decode JSON and hand the route off to your ghost-runner logic
    } else {
      print('Upload failed (${response.statusCode}): ${response.body}');
    }
  } catch (e) {
    print('Error uploading file: $e');
  }
}

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
            // Button row below toolbar
            Container(
              color: const Color.fromARGB(255, 230, 40, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MaterialButton(
                    onPressed: () {
                      _pickFile();
                    },
                    child: Text (
                      'Upload Run',
                      style: TextStyle(color: Colors.black)
                    )),
                  ElevatedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.text_fields, size: 18),
                    label: const Text('Input'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color.fromARGB(255, 255, 50, 50),
                      disabledBackgroundColor: Colors.white,
                      disabledForegroundColor: const Color.fromARGB(255, 255, 50, 50),
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
                        onPressed: null,
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
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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