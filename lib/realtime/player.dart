import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'steering.dart';

class Player extends CircleComponent {
  Player({required Vector2 position})
      : super(
          radius: 22,
          position: position,
          anchor: Anchor.center,
          paint: Paint()..color = const Color(0xFF3478F6),
        );

  Vector2 velocity = Vector2.zero();
  Vector2? _target;

  static const double maxSpeed = 260;
  static const double maxAccel = 600;

  void moveTo(Vector2 target) {
    _target = target.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = _target;
    if (target == null) return;
    velocity = seek(
      position: position,
      velocity: velocity,
      target: target,
      maxSpeed: maxSpeed,
      maxAccel: maxAccel,
      dt: dt,
    );
    position += velocity * dt;
    if ((target - position).length < 2) _target = null;
  }
}
