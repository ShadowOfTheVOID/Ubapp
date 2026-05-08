enum MafiaRole { mafia, doctor, villager }

extension MafiaRoleX on MafiaRole {
  String get displayName => switch (this) {
        MafiaRole.mafia => 'Mafia',
        MafiaRole.doctor => 'Doctor',
        MafiaRole.villager => 'Villager',
      };

  String get tagline => switch (this) {
        MafiaRole.mafia =>
          'Eliminate the town. Coordinate with your fellow mafia at night.',
        MafiaRole.doctor =>
          'Save one player each night. You can self-save once per game.',
        MafiaRole.villager =>
          'You have no special ability. Use your vote during the day.',
      };

  bool get isTown => this != MafiaRole.mafia;
  bool get hasNightAction => this == MafiaRole.mafia || this == MafiaRole.doctor;
}
