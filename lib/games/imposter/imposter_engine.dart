import 'dart:math';

import 'imposter_words.dart';

enum ImposterPhase { lobby, playing, voting, result, gameOver }

enum ImposterWinner { town, imposter }

class ImposterPlayer {
  ImposterPlayer({required this.id, required this.name, required this.isHost});
  final String id;
  final String name;
  final bool isHost;
  bool isImposter = false;
}

class ImposterEngine {
  ImposterEngine({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;
  final Map<String, ImposterPlayer> players = {};
  ImposterPhase phase = ImposterPhase.lobby;

  String category = '';
  String secretWord = '';
  String? imposterId;

  /// Day votes: voterId -> targetId (or null = skip).
  final Map<String, String?> votes = {};
  String? mostVotedId;
  bool? imposterCaught;
  ImposterWinner? winner;

  // ---- Lobby ----
  ImposterPlayer addPlayer({required String id, required String name, bool isHost = false}) {
    final p = ImposterPlayer(id: id, name: name, isHost: isHost);
    players[id] = p;
    return p;
  }

  void removePlayer(String id) {
    if (phase != ImposterPhase.lobby) return;
    players.remove(id);
  }

  bool get canStart => phase == ImposterPhase.lobby && players.length >= 3;

  Iterable<String> get availableCategories => imposterCategories.keys;

  void start({String? categoryName}) {
    if (!canStart) return;
    final cats = imposterCategories.keys.toList();
    category = (categoryName != null && imposterCategories.containsKey(categoryName))
        ? categoryName
        : cats[_rng.nextInt(cats.length)];
    final words = imposterCategories[category]!;
    secretWord = words[_rng.nextInt(words.length)];
    final ids = players.keys.toList();
    imposterId = ids[_rng.nextInt(ids.length)];
    for (final p in players.values) {
      p.isImposter = p.id == imposterId;
    }
    phase = ImposterPhase.playing;
  }

  // ---- Voting ----
  void beginVoting() {
    if (phase != ImposterPhase.playing) return;
    votes.clear();
    phase = ImposterPhase.voting;
  }

  bool submitVote(String voterId, String? targetId) {
    if (phase != ImposterPhase.voting) return false;
    if (!players.containsKey(voterId)) return false;
    if (targetId != null && !players.containsKey(targetId)) return false;
    votes[voterId] = targetId;
    return votes.length == players.length;
  }

  void resolveVotes() {
    final tally = <String, int>{};
    for (final v in votes.values) {
      if (v == null) continue;
      tally[v] = (tally[v] ?? 0) + 1;
    }
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
    mostVotedId = tied.length == 1 ? tied.first : null;
    imposterCaught = mostVotedId == imposterId;
    winner = (imposterCaught ?? false) ? ImposterWinner.town : ImposterWinner.imposter;
    phase = ImposterPhase.result;
  }

  void reset() {
    phase = ImposterPhase.lobby;
    category = '';
    secretWord = '';
    imposterId = null;
    votes.clear();
    mostVotedId = null;
    imposterCaught = null;
    winner = null;
    for (final p in players.values) {
      p.isImposter = false;
    }
  }
}
