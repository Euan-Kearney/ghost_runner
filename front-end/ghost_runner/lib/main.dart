import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

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
    print('File Name: ${file.name}');
    print('File Size: ${file.size} bytes');
    print('File Path: ${file.path}');

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
        final List<dynamic> route =
            decoded['route']; 
        print('Route received: ${response.body}');
        print('Route length: ${route.length}');
        // TODO: decode JSON and hand the route off to your ghost-runner logic.
      } else {
        print('Upload failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('Error uploading file: $e');
    }
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
