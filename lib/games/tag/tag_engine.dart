import 'dart:math';

import 'tag_protocol.dart';
import 'tag_variant.dart';

enum PlayerStatus { runner, it, frozen, eliminated }

class PlayerView {
  PlayerView({
    required this.id,
    required this.displayName,
    required this.status,
  });

  final String id;
  final String displayName;
  PlayerStatus status;
}

class TagState {
  TagState({
    required this.variant,
    required this.players,
    required this.startedAtMs,
    required this.deadlineMs,
    this.endReason,
    this.winnerId,
  });

  final TagVariant variant;
  final Map<String, PlayerView> players;
  final int startedAtMs;
  final int deadlineMs;
  String? endReason;
  String? winnerId;

  bool get isOver => endReason != null;

  Iterable<PlayerView> get its =>
      players.values.where((p) => p.status == PlayerStatus.it);
  Iterable<PlayerView> get runners =>
      players.values.where((p) => p.status == PlayerStatus.runner);
  Iterable<PlayerView> get frozen =>
      players.values.where((p) => p.status == PlayerStatus.frozen);
  Iterable<PlayerView> get alive => players.values
      .where((p) => p.status != PlayerStatus.eliminated);
}

/// Deterministic state machine — given the same `start` + ordered events,
/// every device computes the same state. No randomness here; the host picks
/// the starting "it" once and broadcasts.
class TagEngine {
  TagEngine({required this.selfId});

  final String selfId;
  TagState? state;

  TagState start(StartMessage start, Map<String, String> displayNames) {
    final players = <String, PlayerView>{};
    for (final id in start.peerIds) {
      players[id] = PlayerView(
        id: id,
        displayName: displayNames[id] ?? id.substring(0, min(6, id.length)),
        status: id == start.startingItId ? PlayerStatus.it : PlayerStatus.runner,
      );
    }
    final duration = start.variant == TagVariant.hotPotato
        ? const Duration(minutes: 10) // outer cap; per-tag countdown handled by UI
        : start.variant.duration;
    state = TagState(
      variant: start.variant,
      players: players,
      startedAtMs: start.startTimeMs,
      deadlineMs: start.startTimeMs + duration.inMilliseconds,
    );
    return state!;
  }

  /// Apply a tag event. Returns true if it actually mutated state.
  bool applyTag(TagEvent event) {
    final s = state;
    if (s == null || s.isOver) return false;
    final tagger = s.players[event.taggerId];
    final victim = s.players[event.victimId];
    if (tagger == null || victim == null) return false;
    if (tagger.status != PlayerStatus.it) return false;
    if (victim.status != PlayerStatus.runner) return false;

    switch (s.variant) {
      case TagVariant.classic:
      case TagVariant.bomb:
        tagger.status = PlayerStatus.runner;
        victim.status = PlayerStatus.it;

      case TagVariant.freeze:
        victim.status = PlayerStatus.frozen;
        if (s.runners.isEmpty) {
          s.endReason = 'all_frozen';
          s.winnerId = tagger.id;
        }

      case TagVariant.zombie:
        victim.status = PlayerStatus.it;
        if (s.runners.isEmpty) {
          s.endReason = 'last_survivor';
        }

      case TagVariant.hotPotato:
        tagger.status = PlayerStatus.runner;
        victim.status = PlayerStatus.it;
    }
    return true;
  }

  /// Freeze-tag only: a runner unfreezes a frozen teammate.
  bool applyUnfreeze(UnfreezeEvent event) {
    final s = state;
    if (s == null || s.isOver) return false;
    if (s.variant != TagVariant.freeze) return false;
    final unfreezer = s.players[event.unfreezerId];
    final victim = s.players[event.victimId];
    if (unfreezer == null || victim == null) return false;
    if (unfreezer.status != PlayerStatus.runner) return false;
    if (victim.status != PlayerStatus.frozen) return false;
    victim.status = PlayerStatus.runner;
    return true;
  }

  void applyEnd(EndMessage end) {
    final s = state;
    if (s == null || s.isOver) return;
    s.endReason = end.reason;
    s.winnerId = end.winnerId;
  }

  /// Hot-potato only: caller owns the per-tag countdown. If it expires while
  /// this device is "it", call this to lose.
  EndMessage? hotPotatoTimeout() {
    final s = state;
    if (s == null || s.isOver) return null;
    if (s.variant != TagVariant.hotPotato) return null;
    final me = s.players[selfId];
    if (me?.status != PlayerStatus.it) return null;
    me!.status = PlayerStatus.eliminated;
    final survivor = s.alive.firstOrNull;
    return EndMessage(reason: 'hot_potato_timeout', winnerId: survivor?.id);
  }
}

