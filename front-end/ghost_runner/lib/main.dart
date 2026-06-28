import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {


void _pickFile() async {
  // Opens the file picker. The selected file(s) are returned in the result.
  // If no file is chosen, result will be null.
  // You can set allowMultiple: true if multiple selection is needed.
  final FilePickerResult? result = await FilePicker.pickFiles(
    allowMultiple: false,
  );

  // If no file is picked
  if (result == null) return;

  // Access the first picked file (when allowMultiple is false)
  final PlatformFile file = result.files.first;

  print('File Name: ${file.name}');
  print('File Size: ${file.size} bytes');
  print('File Path: ${file.path}');
}


  const MyApp({super.key});
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