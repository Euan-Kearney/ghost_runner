import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
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
                  IconButton(
                    icon: const Icon(Icons.upload_file, color: Colors.white),
                    onPressed: null,
                    tooltip: 'Upload file',
                  ),
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