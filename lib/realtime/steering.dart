import 'package:flame/components.dart';

/// Seek-style steering: accelerates `velocity` toward a desired velocity that
/// points at `target` at `maxSpeed`, capped by `maxAccel`. Returns the new
/// velocity. Mutating components apply this via `position += velocity * dt`.
Vector2 seek({
  required Vector2 position,
  required Vector2 velocity,
  required Vector2 target,
  required double maxSpeed,
  required double maxAccel,
  required double dt,
}) {
  final toTarget = target - position;
  final dist = toTarget.length;
  if (dist < 1) return Vector2.zero();

  final desired = toTarget / dist * maxSpeed;
  final delta = desired - velocity;
  final maxStep = maxAccel * dt;
  if (delta.length > maxStep) {
    delta.scaleTo(maxStep);
  }
  return velocity + delta;
}
