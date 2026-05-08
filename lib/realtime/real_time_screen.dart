import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'real_time_game.dart';

class RealTimeScreen extends StatefulWidget {
  const RealTimeScreen({super.key});

  @override
  State<RealTimeScreen> createState() => _RealTimeScreenState();
}

class _RealTimeScreenState extends State<RealTimeScreen> {
  late final RealTimeGame _game = RealTimeGame();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Real-time')),
      body: GameWidget(game: _game),
    );
  }
}
