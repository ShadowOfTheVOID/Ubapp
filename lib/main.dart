import 'package:flutter/material.dart';

import 'menu/main_menu_screen.dart';

void main() {
  runApp(const UbappApp());
}

class UbappApp extends StatelessWidget {
  const UbappApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ubapp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainMenuScreen(),
    );
  }
}
