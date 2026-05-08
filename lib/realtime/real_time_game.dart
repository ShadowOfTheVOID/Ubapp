import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'enemy.dart';
import 'player.dart';

class RealTimeGame extends FlameGame with TapCallbacks {
  late Player _player;
  final _rng = Random();
  bool _spawned = false;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    final hud = TextComponent(
      text: 'Tap to move. Enemies wander, then chase.',
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      position: Vector2(12, 12),
    );
    add(hud);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!_spawned && size.x > 0 && size.y > 0) {
      _spawnWorld();
      _spawned = true;
    }
  }

  void _spawnWorld() {
    _player = Player(position: size / 2);
    add(_player);

    for (var i = 0; i < 4; i++) {
      add(Enemy(
        position: Vector2(_rng.nextDouble() * size.x, _rng.nextDouble() * size.y),
        target: _player,
        bounds: size,
      ));
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!_spawned) return;
    _player.moveTo(event.localPosition);
  }
}
