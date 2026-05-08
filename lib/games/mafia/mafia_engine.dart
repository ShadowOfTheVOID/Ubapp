import 'dart:math';

import 'mafia_role.dart';

enum MafiaPhase { lobby, night, dayReveal, dayVote, gameOver }

enum Winner { mafia, town }

class Player {
  Player({required this.id, required this.name, required this.isHost});
  final String id;
  final String name;
  final bool isHost;
  MafiaRole? role;
  bool alive = true;
}

class NightOutcome {
  NightOutcome({this.killedId, this.savedId});
  final String? killedId;
  final String? savedId;
}

class DayOutcome {
  DayOutcome({this.eliminatedId, required this.tally});
  final String? eliminatedId;
  final Map<String, int> tally;
}

/// Pure game logic. The server adapter is responsible for collecting
/// messages and feeding them in; the engine never touches network code.
class MafiaEngine {
  MafiaEngine({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;
  final Map<String, Player> players = {};
  MafiaPhase phase = MafiaPhase.lobby;
  int day = 0;
  Winner? winner;

  /// Per-night submissions: roleId -> targetId. Mafia votes are tallied
  /// across all live mafia.
  final Map<String, String> _mafiaVotes = {};
  String? _doctorTarget;
  bool _doctorSelfSaveUsed = false;

  /// Day votes: voterId -> targetId (or null = skip).
  final Map<String, String?> dayVotes = {};

  NightOutcome? lastNight;
  DayOutcome? lastDay;

  // ---- Lobby -----------------------------------------------------------

  Player addPlayer({required String id, required String name, bool isHost = false}) {
    final p = Player(id: id, name: name, isHost: isHost);
    players[id] = p;
    return p;
  }

  void removePlayer(String id) {
    if (phase != MafiaPhase.lobby) return;
    players.remove(id);
  }

  bool get canStart => phase == MafiaPhase.lobby && players.length >= 4;

  void start() {
    if (!canStart) return;
    final ids = players.keys.toList()..shuffle(_rng);
    final mafiaCount = (ids.length / 4).floor().clamp(1, ids.length - 2);

    for (var i = 0; i < ids.length; i++) {
      final p = players[ids[i]]!;
      if (i < mafiaCount) {
        p.role = MafiaRole.mafia;
      } else if (i == mafiaCount) {
        p.role = MafiaRole.doctor;
      } else {
        p.role = MafiaRole.villager;
      }
    }
    phase = MafiaPhase.night;
    day = 1;
  }

  // ---- Night -----------------------------------------------------------

  Iterable<Player> get aliveMafia => players.values
      .where((p) => p.alive && p.role == MafiaRole.mafia);
  Iterable<Player> get aliveDoctors => players.values
      .where((p) => p.alive && p.role == MafiaRole.doctor);
  Iterable<Player> get alive => players.values.where((p) => p.alive);
  Iterable<Player> get dead => players.values.where((p) => !p.alive);

  /// Mafia member submits a kill vote. Returns true once enough votes are in
  /// for the night to be ready to resolve.
  bool submitMafiaVote(String voterId, String targetId) {
    if (phase != MafiaPhase.night) return false;
    final voter = players[voterId];
    if (voter == null || !voter.alive || voter.role != MafiaRole.mafia) {
      return false;
    }
    final target = players[targetId];
    if (target == null || !target.alive) return false;
    _mafiaVotes[voterId] = targetId;
    return _isNightReady();
  }

  bool submitDoctorTarget(String doctorId, String targetId) {
    if (phase != MafiaPhase.night) return false;
    final doc = players[doctorId];
    if (doc == null || !doc.alive || doc.role != MafiaRole.doctor) return false;
    final target = players[targetId];
    if (target == null || !target.alive) return false;
    if (targetId == doctorId && _doctorSelfSaveUsed) return false;
    _doctorTarget = targetId;
    return _isNightReady();
  }

  bool _isNightReady() {
    final mafiaSubmitted = aliveMafia.every((m) => _mafiaVotes.containsKey(m.id));
    final doctorSubmitted = aliveDoctors.isEmpty || _doctorTarget != null;
    return mafiaSubmitted && doctorSubmitted;
  }

  NightOutcome resolveNight() {
    final tally = <String, int>{};
    for (final t in _mafiaVotes.values) {
      tally[t] = (tally[t] ?? 0) + 1;
    }
    String? killTarget;
    int max = 0;
    final tied = <String>[];
    tally.forEach((id, count) {
      if (count > max) {
        max = count;
        tied
          ..clear()
          ..add(id);
      } else if (count == max) {
        tied.add(id);
      }
    });
    if (tied.length == 1) killTarget = tied.first;

    String? saved;
    if (_doctorTarget != null && _doctorTarget == killTarget) {
      saved = _doctorTarget;
      if (saved == aliveDoctors.firstOrNull?.id) _doctorSelfSaveUsed = true;
      killTarget = null;
    }

    if (killTarget != null) {
      final p = players[killTarget];
      if (p != null) p.alive = false;
    }

    lastNight = NightOutcome(killedId: killTarget, savedId: saved);
    _mafiaVotes.clear();
    _doctorTarget = null;
    phase = MafiaPhase.dayReveal;
    return lastNight!;
  }

  void advanceToDayVote() {
    if (phase != MafiaPhase.dayReveal) return;
    dayVotes.clear();
    if (_checkWin()) return;
    phase = MafiaPhase.dayVote;
  }

  // ---- Day vote --------------------------------------------------------

  bool submitDayVote(String voterId, String? targetId) {
    if (phase != MafiaPhase.dayVote) return false;
    final voter = players[voterId];
    if (voter == null || !voter.alive) return false;
    if (targetId != null) {
      final t = players[targetId];
      if (t == null || !t.alive) return false;
    }
    dayVotes[voterId] = targetId;
    return alive.every((p) => dayVotes.containsKey(p.id));
  }

  DayOutcome resolveDay() {
    final tally = <String, int>{};
    for (final t in dayVotes.values) {
      if (t == null) continue;
      tally[t] = (tally[t] ?? 0) + 1;
    }

    String? eliminated;
    int max = 0;
    final tied = <String>[];
    tally.forEach((id, count) {
      if (count > max) {
        max = count;
        tied
          ..clear()
          ..add(id);
      } else if (count == max) {
        tied.add(id);
      }
    });
    if (tied.length == 1 && max > alive.length / 2) eliminated = tied.first;

    if (eliminated != null) {
      players[eliminated]!.alive = false;
    }
    lastDay = DayOutcome(eliminatedId: eliminated, tally: tally);

    if (_checkWin()) return lastDay!;
    day += 1;
    phase = MafiaPhase.night;
    return lastDay!;
  }

  bool _checkWin() {
    final liveMafia = aliveMafia.length;
    final liveTown = alive.where((p) => p.role != MafiaRole.mafia).length;
    if (liveMafia == 0) {
      winner = Winner.town;
      phase = MafiaPhase.gameOver;
      return true;
    }
    if (liveMafia >= liveTown) {
      winner = Winner.mafia;
      phase = MafiaPhase.gameOver;
      return true;
    }
    return false;
  }
}
