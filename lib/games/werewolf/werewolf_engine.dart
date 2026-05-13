import 'dart:math';

import '../../tutorials/tutorial_vote.dart';
import 'werewolf_role.dart';

enum WerewolfPhase { lobby, night, dayReveal, dayVote, hunterShot, gameOver }

enum Winner { werewolves, town }

class Player {
  Player({required this.id, required this.name, required this.isHost});
  final String id;
  final String name;
  final bool isHost;
  WerewolfRole? role;
  bool alive = true;
}

class NightOutcome {
  NightOutcome({this.killedId});
  final String? killedId;
}

class DayOutcome {
  DayOutcome({this.eliminatedId, required this.tally});
  final String? eliminatedId;
  final Map<String, int> tally;
}

class SeerResult {
  SeerResult({required this.seerId, required this.targetId, required this.isWerewolf});
  final String seerId;
  final String targetId;
  final bool isWerewolf;
}

class HunterShot {
  HunterShot({required this.hunterId, required this.targetId});
  final String hunterId;
  final String targetId;
}

/// Pure game logic. The server adapter is responsible for collecting
/// messages and feeding them in; the engine never touches network code.
class WerewolfEngine {
  WerewolfEngine({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;
  final Map<String, Player> players = {};
  WerewolfPhase phase = WerewolfPhase.lobby;
  int day = 0;
  Winner? winner;

  /// Per-night submissions.
  final Map<String, String> _wolfVotes = {};
  String? _seerTarget;

  /// Day votes: voterId -> targetId (or null = skip).
  final Map<String, String?> dayVotes = {};

  /// When a hunter dies, they get to shoot before play resumes. The
  /// engine parks on [WerewolfPhase.hunterShot] until the shot is in,
  /// and a fresh hunter death from that shot keeps us parked (chain).
  String? pendingHunterShooter;
  WerewolfPhase? _postHunterPhase;

  NightOutcome? lastNight;
  DayOutcome? lastDay;
  SeerResult? lastSeerResult;
  final List<HunterShot> hunterShotsThisRound = [];

  final TutorialVote tutorialVote = TutorialVote();

  // ---- Lobby -----------------------------------------------------------

  Player addPlayer({required String id, required String name, bool isHost = false}) {
    final p = Player(id: id, name: name, isHost: isHost);
    players[id] = p;
    return p;
  }

  void removePlayer(String id) {
    if (phase != WerewolfPhase.lobby) return;
    players.remove(id);
  }

  bool get canStart => phase == WerewolfPhase.lobby && players.length >= 5;

  void start() {
    if (!canStart) return;
    final ids = players.keys.toList()..shuffle(_rng);
    final wolfCount = (ids.length / 5).floor().clamp(1, ids.length - 3);
    final includeHunter = ids.length >= 6;

    var i = 0;
    for (; i < wolfCount; i++) {
      players[ids[i]]!.role = WerewolfRole.werewolf;
    }
    players[ids[i++]]!.role = WerewolfRole.seer;
    if (includeHunter) {
      players[ids[i++]]!.role = WerewolfRole.hunter;
    }
    for (; i < ids.length; i++) {
      players[ids[i]]!.role = WerewolfRole.villager;
    }
    phase = WerewolfPhase.night;
    day = 1;
  }

  // ---- Night -----------------------------------------------------------

  Iterable<Player> get aliveWolves => players.values
      .where((p) => p.alive && p.role == WerewolfRole.werewolf);
  Iterable<Player> get aliveSeers => players.values
      .where((p) => p.alive && p.role == WerewolfRole.seer);
  Iterable<Player> get alive => players.values.where((p) => p.alive);
  Iterable<Player> get dead => players.values.where((p) => !p.alive);

  /// A werewolf submits a kill vote. Returns true once all wolves + seer
  /// have submitted and the night is ready to resolve.
  bool submitWolfVote(String voterId, String targetId) {
    if (phase != WerewolfPhase.night) return false;
    final voter = players[voterId];
    if (voter == null || !voter.alive || voter.role != WerewolfRole.werewolf) {
      return false;
    }
    final target = players[targetId];
    if (target == null || !target.alive) return false;
    if (target.role == WerewolfRole.werewolf) return false;
    _wolfVotes[voterId] = targetId;
    return _isNightReady();
  }

  bool submitSeerTarget(String seerId, String targetId) {
    if (phase != WerewolfPhase.night) return false;
    final seer = players[seerId];
    if (seer == null || !seer.alive || seer.role != WerewolfRole.seer) {
      return false;
    }
    final target = players[targetId];
    if (target == null || !target.alive) return false;
    if (targetId == seerId) return false;
    _seerTarget = targetId;
    return _isNightReady();
  }

  bool _isNightReady() {
    final wolvesSubmitted = aliveWolves.every((w) => _wolfVotes.containsKey(w.id));
    final seerSubmitted = aliveSeers.isEmpty || _seerTarget != null;
    return wolvesSubmitted && seerSubmitted;
  }

  NightOutcome resolveNight() {
    final tally = <String, int>{};
    for (final t in _wolfVotes.values) {
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

    if (_seerTarget != null) {
      final seer = aliveSeers.firstOrNull;
      final target = players[_seerTarget];
      if (seer != null && target != null) {
        lastSeerResult = SeerResult(
          seerId: seer.id,
          targetId: target.id,
          isWerewolf: target.role == WerewolfRole.werewolf,
        );
      }
    } else {
      lastSeerResult = null;
    }

    hunterShotsThisRound.clear();
    if (killTarget != null) {
      _killPlayer(killTarget);
    }
    lastNight = NightOutcome(killedId: killTarget);
    _wolfVotes.clear();
    _seerTarget = null;

    if (_checkWin()) return lastNight!;
    if (pendingHunterShooter != null) {
      _postHunterPhase = WerewolfPhase.dayReveal;
      phase = WerewolfPhase.hunterShot;
    } else {
      phase = WerewolfPhase.dayReveal;
    }
    return lastNight!;
  }

  void advanceToDayVote() {
    if (phase != WerewolfPhase.dayReveal) return;
    dayVotes.clear();
    if (_checkWin()) return;
    phase = WerewolfPhase.dayVote;
  }

  // ---- Day vote --------------------------------------------------------

  bool submitDayVote(String voterId, String? targetId) {
    if (phase != WerewolfPhase.dayVote) return false;
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

    hunterShotsThisRound.clear();
    if (eliminated != null) {
      _killPlayer(eliminated);
    }
    lastDay = DayOutcome(eliminatedId: eliminated, tally: tally);

    if (_checkWin()) return lastDay!;
    if (pendingHunterShooter != null) {
      _postHunterPhase = WerewolfPhase.night;
      phase = WerewolfPhase.hunterShot;
    } else {
      day += 1;
      phase = WerewolfPhase.night;
    }
    return lastDay!;
  }

  // ---- Hunter shot -----------------------------------------------------

  bool submitHunterShot(String hunterId, String targetId) {
    if (phase != WerewolfPhase.hunterShot) return false;
    if (pendingHunterShooter != hunterId) return false;
    final target = players[targetId];
    if (target == null || !target.alive) return false;
    if (targetId == hunterId) return false;

    pendingHunterShooter = null;
    hunterShotsThisRound.add(HunterShot(hunterId: hunterId, targetId: targetId));
    _killPlayer(targetId);

    if (_checkWin()) return true;
    if (pendingHunterShooter != null) {
      // Chain: another hunter just died — stay parked in hunterShot.
      return true;
    }
    final returnTo = _postHunterPhase ?? WerewolfPhase.dayReveal;
    _postHunterPhase = null;
    if (returnTo == WerewolfPhase.night) {
      day += 1;
    }
    phase = returnTo;
    return true;
  }

  // ---- Internal --------------------------------------------------------

  void _killPlayer(String id) {
    final p = players[id];
    if (p == null || !p.alive) return;
    p.alive = false;
    if (p.role == WerewolfRole.hunter) {
      pendingHunterShooter = id;
    }
  }

  bool _checkWin() {
    final liveWolves = aliveWolves.length;
    final liveTown = alive.where((p) => p.role != WerewolfRole.werewolf).length;
    if (liveWolves == 0) {
      winner = Winner.town;
      phase = WerewolfPhase.gameOver;
      return true;
    }
    if (liveWolves >= liveTown) {
      winner = Winner.werewolves;
      phase = WerewolfPhase.gameOver;
      return true;
    }
    return false;
  }
}
