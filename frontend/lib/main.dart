import 'package:flutter/material.dart';

import 'pages/login_page.dart';

void main() {
  runApp(const GradescopeUploaderApp());
}

class GradescopeUploaderApp extends StatelessWidget {
  const GradescopeUploaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gradescope Uploader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
      ),
      home: const LoginPage(),
    );
  }
}
