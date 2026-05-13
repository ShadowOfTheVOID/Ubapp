enum WerewolfRole { werewolf, seer, hunter, villager }

extension WerewolfRoleX on WerewolfRole {
  String get displayName => switch (this) {
        WerewolfRole.werewolf => 'Werewolf',
        WerewolfRole.seer => 'Seer',
        WerewolfRole.hunter => 'Hunter',
        WerewolfRole.villager => 'Villager',
      };

  String get tagline => switch (this) {
        WerewolfRole.werewolf =>
          'Hunt the village. Coordinate with your pack at night.',
        WerewolfRole.seer =>
          'Each night, learn whether one player is a werewolf.',
        WerewolfRole.hunter =>
          'When you die, you take one player down with you.',
        WerewolfRole.villager =>
          'No special ability. Survive and vote wisely.',
      };

  bool get isTown => this != WerewolfRole.werewolf;
  bool get hasNightAction =>
      this == WerewolfRole.werewolf || this == WerewolfRole.seer;
}
