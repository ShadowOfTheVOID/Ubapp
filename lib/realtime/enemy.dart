import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'player.dart';
import 'state_machine.dart';
import 'steering.dart';

class Enemy extends CircleComponent {
  Enemy({required Vector2 position, required this.target, required this.bounds})
      : super(
          radius: 16,
          position: position,
          anchor: Anchor.center,
          paint: Paint()..color = Colors.grey,
        );

  final Player target;
  final Vector2 bounds;

  Vector2 velocity = Vector2.zero();
  Vector2 wanderTarget = Vector2.zero();
  double maxSpeed = 90;
  double maxAccel = 280;

  late final StateMachine _stateMachine;

  @override
  Future<void> onLoad() async {
    final wander = WanderState(this);
    final chase = ChaseState(this);
    wander.peer = chase;
    chase.peer = wander;
    _stateMachine = StateMachine(wander);
  }

  void transition(GameState next) => _stateMachine.transition(next);

  void steerToward(Vector2 t, double dt) {
    velocity = seek(
      position: position,
      velocity: velocity,
      target: t,
      maxSpeed: maxSpeed,
      maxAccel: maxAccel,
      dt: dt,
    );
    position += velocity * dt;
  }

  void setColor(Color c) => paint.color = c;

  @override
  void update(double dt) {
    super.update(dt);
    _stateMachine.update(dt);
  }
}

const double _chaseRadiusSq = 250 * 250;
const double _giveUpRadiusSq = 400 * 400;

class WanderState extends GameState {
  WanderState(this.enemy);

  final Enemy enemy;
  ChaseState? peer;
  final _rng = Random();
  double _pickTimer = 0;

  @override
  void onEnter() {
    enemy.setColor(Colors.grey);
    enemy.maxSpeed = 90;
    _pickNew();
  }

  @override
  void update(double dt) {
    _pickTimer -= dt;
    if (_pickTimer <= 0) _pickNew();
    enemy.steerToward(enemy.wanderTarget, dt);

    if ((enemy.target.position - enemy.position).length2 < _chaseRadiusSq) {
      final p = peer;
      if (p != null) enemy.transition(p);
    }
  }

  void _pickNew() {
    enemy.wanderTarget = Vector2(
      _rng.nextDouble() * enemy.bounds.x,
      _rng.nextDouble() * enemy.bounds.y,
    );
    _pickTimer = 1.5 + _rng.nextDouble() * 1.5;
  }
}

class ChaseState extends GameState {
  ChaseState(this.enemy);

  final Enemy enemy;
  WanderState? peer;

  @override
  void onEnter() {
    enemy.setColor(Colors.redAccent);
    enemy.maxSpeed = 170;
  }

  @override
  void update(double dt) {
    enemy.steerToward(enemy.target.position, dt);
    if ((enemy.target.position - enemy.position).length2 > _giveUpRadiusSq) {
      final p = peer;
      if (p != null) enemy.transition(p);
    }
  }
}
