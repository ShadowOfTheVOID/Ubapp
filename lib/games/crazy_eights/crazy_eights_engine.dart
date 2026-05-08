import 'dart:math';

import 'card.dart';

enum CrazyEightsPhase { lobby, playing, gameOver }

class CrazyEightsPlayer {
  CrazyEightsPlayer({required this.id, required this.name, required this.isHost});
  final String id;
  final String name;
  final bool isHost;
  final List<Card> hand = [];
}

/// Classic Crazy Eights:
///   - Match top card by suit or rank
///   - 8s are wild — player picks new active suit
///   - If you can't play, draw one card (if it's playable, you may play it)
///   - First empty hand wins
class CrazyEightsEngine {
  CrazyEightsEngine({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;
  final Map<String, CrazyEightsPlayer> players = {};
  final List<String> _order = [];
  CrazyEightsPhase phase = CrazyEightsPhase.lobby;

  final List<Card> drawPile = [];
  final List<Card> discardPile = [];
  Suit? activeSuit; // overrides top card suit when an 8 is played
  int currentIndex = 0;
  bool justDrew = false;
  String? winnerId;
  String? lastEvent;

  CrazyEightsPlayer? get current =>
      _order.isEmpty ? null : players[_order[currentIndex]];

  Card? get topCard => discardPile.isEmpty ? null : discardPile.last;

  Suit get activeOrTopSuit => activeSuit ?? topCard!.suit;

  // ---- Lobby ----
  CrazyEightsPlayer addPlayer({required String id, required String name, bool isHost = false}) {
    final p = CrazyEightsPlayer(id: id, name: name, isHost: isHost);
    players[id] = p;
    return p;
  }

  void removePlayer(String id) {
    if (phase != CrazyEightsPhase.lobby) return;
    players.remove(id);
  }

  bool get canStart =>
      phase == CrazyEightsPhase.lobby && players.length >= 2 && players.length <= 8;

  void start() {
    if (!canStart) return;
    drawPile.clear();
    discardPile.clear();
    activeSuit = null;
    drawPile.addAll(standardDeck()..shuffle(_rng));

    final dealCount = players.length == 2 ? 7 : 5;
    _order
      ..clear()
      ..addAll(players.keys.toList()..shuffle(_rng));
    for (var i = 0; i < dealCount; i++) {
      for (final pid in _order) {
        players[pid]!.hand.add(drawPile.removeLast());
      }
    }

    // Flip first non-8 card to start. Eights start the active suit fresh.
    while (drawPile.isNotEmpty) {
      final c = drawPile.removeLast();
      discardPile.add(c);
      if (c.rank != 8) break;
    }
    currentIndex = 0;
    justDrew = false;
    phase = CrazyEightsPhase.playing;
    lastEvent = '${current!.name} starts';
  }

  // ---- Play / draw ----
  bool canPlay(Card c) {
    final top = topCard;
    if (top == null) return true;
    if (c.rank == 8) return true;
    if (c.suit == activeOrTopSuit) return true;
    if (c.rank == top.rank) return true;
    return false;
  }

  /// Returns null on success, an error message on failure.
  String? playCard(String playerId, Card card, {Suit? declaredSuit}) {
    if (phase != CrazyEightsPhase.playing) return 'not playing';
    final p = players[playerId];
    if (p == null) return 'unknown player';
    if (p.id != current!.id) return 'not your turn';
    final inHand = p.hand.firstWhere(
        (c) => c == card,
        orElse: () => const Card(Suit.clubs, 0));
    if (inHand.rank == 0) return 'card not in hand';
    if (!canPlay(card)) return 'card does not match';
    if (card.rank == 8 && declaredSuit == null) return 'must declare a suit';

    p.hand.remove(card);
    discardPile.add(card);
    activeSuit = card.rank == 8 ? declaredSuit : null;
    justDrew = false;
    lastEvent = card.rank == 8
        ? '${p.name} played $card → ${declaredSuit!.glyph}'
        : '${p.name} played $card';

    if (p.hand.isEmpty) {
      phase = CrazyEightsPhase.gameOver;
      winnerId = p.id;
      return null;
    }
    _advanceTurn();
    return null;
  }

  /// Draws one card. If the drawn card is playable, the player may play it
  /// (their turn doesn't end yet). If not, turn passes.
  Card? drawOne(String playerId) {
    if (phase != CrazyEightsPhase.playing) return null;
    final p = players[playerId];
    if (p == null || p.id != current!.id) return null;
    if (drawPile.isEmpty) _reshuffle();
    if (drawPile.isEmpty) {
      // no cards available at all — pass
      _advanceTurn();
      return null;
    }
    final c = drawPile.removeLast();
    p.hand.add(c);
    lastEvent = '${p.name} drew a card';
    if (canPlay(c)) {
      justDrew = true;
      return c;
    }
    justDrew = false;
    _advanceTurn();
    return c;
  }

  /// Pass after a draw if the drawn card is unplayable or you choose not to.
  void passAfterDraw(String playerId) {
    final p = players[playerId];
    if (p == null || p.id != current!.id) return;
    if (!justDrew) return;
    justDrew = false;
    lastEvent = '${p.name} passed';
    _advanceTurn();
  }

  void _advanceTurn() {
    currentIndex = (currentIndex + 1) % _order.length;
    justDrew = false;
  }

  void _reshuffle() {
    if (discardPile.length <= 1) return;
    final top = discardPile.removeLast();
    drawPile.addAll(discardPile..shuffle(_rng));
    discardPile
      ..clear()
      ..add(top);
  }

  void reset() {
    phase = CrazyEightsPhase.lobby;
    drawPile.clear();
    discardPile.clear();
    activeSuit = null;
    currentIndex = 0;
    justDrew = false;
    winnerId = null;
    lastEvent = null;
    for (final p in players.values) {
      p.hand.clear();
    }
  }
}
