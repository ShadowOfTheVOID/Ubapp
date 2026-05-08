import 'package:flutter/material.dart';

enum TagVariant {
  classic,
  freeze,
  zombie,
  hotPotato,
  bomb,
}

extension TagVariantX on TagVariant {
  String get displayName => switch (this) {
        TagVariant.classic => 'Classic',
        TagVariant.freeze => 'Freeze tag',
        TagVariant.zombie => 'Zombie',
        TagVariant.hotPotato => 'Hot potato',
        TagVariant.bomb => 'Bomb',
      };

  String get tagline => switch (this) {
        TagVariant.classic => 'Tagger transfers the role on contact.',
        TagVariant.freeze => 'Tagged players freeze. Teammates can unfreeze them.',
        TagVariant.zombie => 'Tagged players become it too. Last survivor wins.',
        TagVariant.hotPotato => 'It must tag before the timer runs out — or they lose.',
        TagVariant.bomb => 'Only it knows their role. Tag before the hidden timer ends.',
      };

  IconData get icon => switch (this) {
        TagVariant.classic => Icons.directions_run,
        TagVariant.freeze => Icons.ac_unit,
        TagVariant.zombie => Icons.coronavirus,
        TagVariant.hotPotato => Icons.timer,
        TagVariant.bomb => Icons.local_fire_department,
      };

  Color get accent => switch (this) {
        TagVariant.classic => Colors.blueAccent,
        TagVariant.freeze => Colors.lightBlueAccent,
        TagVariant.zombie => Colors.greenAccent,
        TagVariant.hotPotato => Colors.orangeAccent,
        TagVariant.bomb => Colors.redAccent,
      };

  /// Default round length. Hot potato uses this as the per-tag countdown
  /// rather than the round; bomb uses it as the hidden bomb timer.
  Duration get duration => switch (this) {
        TagVariant.classic => const Duration(minutes: 5),
        TagVariant.freeze => const Duration(minutes: 5),
        TagVariant.zombie => const Duration(minutes: 5),
        TagVariant.hotPotato => const Duration(seconds: 30),
        TagVariant.bomb => const Duration(minutes: 3),
      };

  /// Whether the round can end early due to a special condition (last one
  /// standing, tagger ran out of time, etc.).
  bool get hasEarlyEnd => switch (this) {
        TagVariant.classic => false,
        TagVariant.freeze => true,
        TagVariant.zombie => true,
        TagVariant.hotPotato => true,
        TagVariant.bomb => true,
      };

  /// Whether the variant hides the "it" role from non-it players.
  bool get hidesIt => this == TagVariant.bomb;
}
