import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

/// Main app widget for the bangla_pdf example.
class MyApp extends StatelessWidget {
  /// Creates the app.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bangla PDF Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const ExampleScreen(),
    );
  }
}

/// Example screen demonstrating bangla_pdf usage.
class ExampleScreen extends StatelessWidget {
  /// Creates the example screen.
  const ExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bangla PDF Example'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.picture_as_pdf, size: 64),
            const SizedBox(height: 20),
            const Text(
              'Bangla PDF Generator',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'This example demonstrates the bangla_pdf package with mixed Bangla and English text rendering.',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'See example/lib/services/demo_pdf.dart for PDF generation code',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.file_download),
              label: const Text('View Demo'),
            ),
          ],
        ),
      ),
    );
  }
}
