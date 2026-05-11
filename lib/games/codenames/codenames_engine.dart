import 'dart:math';

import 'codenames_words.dart';

enum Team { red, blue }

enum CardKind { red, blue, neutral, assassin }

enum CodenamesPhase { lobby, playing, gameOver }

extension TeamX on Team {
  Team get other => this == Team.red ? Team.blue : Team.red;
  String get name2 => this == Team.red ? 'red' : 'blue';
}

class CodenamesCard {
  CodenamesCard({required this.word, required this.kind});
  final String word;
  final CardKind kind;
  bool revealed = false;
}

class CodenamesPlayer {
  CodenamesPlayer({required this.id, required this.name, required this.isHost});
  final String id;
  final String name;
  final bool isHost;
  Team? team;
  bool isSpymaster = false;
}

class CodenamesEngine {
  CodenamesEngine({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;
  final Map<String, CodenamesPlayer> players = {};
  CodenamesPhase phase = CodenamesPhase.lobby;

  final List<CodenamesCard> board = [];
  Team startingTeam = Team.red;
  Team currentTeam = Team.red;
  String? currentClue;
  int currentNumber = 0;
  int guessesLeftThisTurn = 0;
  Team? winner;
  String? endReason;
  String? lastEvent;

  // ---- Lobby ----
  CodenamesPlayer addPlayer({required String id, required String name, bool isHost = false}) {
    final p = CodenamesPlayer(id: id, name: name, isHost: isHost);
    players[id] = p;
    return p;
  }

  void removePlayer(String id) {
    if (phase != CodenamesPhase.lobby) return;
    players.remove(id);
  }

  void setTeam(String id, Team team) {
    final p = players[id];
    if (p == null || phase != CodenamesPhase.lobby) return;
    p.team = team;
  }

  void setSpymaster(String id, bool isSpymaster) {
    final p = players[id];
    if (p == null || phase != CodenamesPhase.lobby) return;
    // Only one spymaster per team.
    if (isSpymaster && p.team != null) {
      for (final other in players.values) {
        if (other.id != id && other.team == p.team) other.isSpymaster = false;
      }
    }
    p.isSpymaster = isSpymaster;
  }

  bool get canStart {
    if (phase != CodenamesPhase.lobby) return false;
    if (players.length < 4) return false;
    final red = players.values.where((p) => p.team == Team.red);
    final blue = players.values.where((p) => p.team == Team.blue);
    if (red.length < 2 || blue.length < 2) return false;
    if (!red.any((p) => p.isSpymaster) || !blue.any((p) => p.isSpymaster)) {
      return false;
    }
    return true;
  }

  void start() {
    if (!canStart) return;
    // Pick 25 words.
    final pool = [...codenamesWordBank]..shuffle(_rng);
    final words = pool.take(25).toList();

    // Starting team gets 9 cards, other 8, 7 neutral, 1 assassin.
    startingTeam = _rng.nextBool() ? Team.red : Team.blue;
    currentTeam = startingTeam;
    final kinds = <CardKind>[
      ...List.filled(startingTeam == Team.red ? 9 : 8, CardKind.red),
      ...List.filled(startingTeam == Team.blue ? 9 : 8, CardKind.blue),
      ...List.filled(7, CardKind.neutral),
      CardKind.assassin,
    ]..shuffle(_rng);

    board
      ..clear()
      ..addAll(List.generate(25, (i) => CodenamesCard(word: words[i], kind: kinds[i])));

    phase = CodenamesPhase.playing;
    currentClue = null;
    currentNumber = 0;
    guessesLeftThisTurn = 0;
    winner = null;
    endReason = null;
    lastEvent = 'Game begins. ${currentTeam.name2.toUpperCase()} spymaster, give the first clue.';
  }

  // ---- Playing ----
  /// Spymaster submits a clue. number = how many words on the board this clue
  /// relates to. Agents get number+1 guesses.
  bool submitClue(String spymasterId, String clue, int number) {
    if (phase != CodenamesPhase.playing) return false;
    final p = players[spymasterId];
    if (p == null || !p.isSpymaster || p.team != currentTeam) return false;
    if (currentClue != null) return false; // can't double-clue
    if (clue.trim().isEmpty) return false;
    currentClue = clue.trim();
    currentNumber = number;
    guessesLeftThisTurn = number + 1;
    lastEvent = '${p.name} (${currentTeam.name2}) clue: "$currentClue" $currentNumber';
    return true;
  }

  /// Agent guesses a card. Returns CardKind of revealed card or null if illegal.
  CardKind? guess(String guesserId, int boardIndex) {
    if (phase != CodenamesPhase.playing) return null;
    final p = players[guesserId];
    if (p == null || p.isSpymaster || p.team != currentTeam) return null;
    if (currentClue == null || guessesLeftThisTurn <= 0) return null;
    if (boardIndex < 0 || boardIndex >= 25) return null;
    final card = board[boardIndex];
    if (card.revealed) return null;
    card.revealed = true;

    final teamKind = currentTeam == Team.red ? CardKind.red : CardKind.blue;
    final opponentKind = currentTeam == Team.red ? CardKind.blue : CardKind.red;

    if (card.kind == CardKind.assassin) {
      winner = currentTeam.other;
      endReason = '${currentTeam.name2.toUpperCase()} hit the assassin';
      phase = CodenamesPhase.gameOver;
      lastEvent = '${p.name} guessed ${card.word} — ASSASSIN. ${winner!.name2.toUpperCase()} wins!';
      return card.kind;
    }

    lastEvent = '${p.name} guessed ${card.word} (${card.kind.name})';
    if (card.kind == teamKind) {
      guessesLeftThisTurn -= 1;
      if (_checkBoardWin()) return card.kind;
      if (guessesLeftThisTurn <= 0) _endTurn();
    } else if (card.kind == opponentKind) {
      if (_checkBoardWin()) return card.kind;
      _endTurn();
    } else {
      // neutral
      if (_checkBoardWin()) return card.kind;
      _endTurn();
    }
    return card.kind;
  }

  /// Agent can voluntarily end their turn (after at least one guess).
  void endTurn(String guesserId) {
    if (phase != CodenamesPhase.playing) return;
    final p = players[guesserId];
    if (p == null || p.isSpymaster || p.team != currentTeam) return;
    if (currentClue == null) return;
    if (guessesLeftThisTurn == currentNumber + 1) return; // haven't guessed yet
    _endTurn();
  }

  void _endTurn() {
    currentTeam = currentTeam.other;
    currentClue = null;
    currentNumber = 0;
    guessesLeftThisTurn = 0;
    lastEvent =
        '${(lastEvent ?? '').isEmpty ? '' : '$lastEvent. '}Turn passes to ${currentTeam.name2.toUpperCase()}.';
  }

  bool _checkBoardWin() {
    final redLeft = board
        .where((c) => !c.revealed && c.kind == CardKind.red)
        .length;
    final blueLeft = board
        .where((c) => !c.revealed && c.kind == CardKind.blue)
        .length;
    if (redLeft == 0) {
      winner = Team.red;
      endReason = 'red found all their words';
      phase = CodenamesPhase.gameOver;
      return true;
    }
    if (blueLeft == 0) {
      winner = Team.blue;
      endReason = 'blue found all their words';
      phase = CodenamesPhase.gameOver;
      return true;
    }
    return false;
  }

  int cardsLeftFor(Team team) {
    final kind = team == Team.red ? CardKind.red : CardKind.blue;
    return board.where((c) => !c.revealed && c.kind == kind).length;
  }

  void reset() {
    phase = CodenamesPhase.lobby;
    board.clear();
    currentClue = null;
    currentNumber = 0;
    guessesLeftThisTurn = 0;
    winner = null;
    endReason = null;
    lastEvent = null;
  }
}
