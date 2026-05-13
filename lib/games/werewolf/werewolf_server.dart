import 'dart:async';
import 'dart:convert';

import '../../social/host_server.dart';
import 'werewolf_browser.dart';
import 'werewolf_engine.dart';
import 'werewolf_role.dart';

/// Wraps [HostServer] with Werewolf-specific routing. Owns the engine,
/// fans out the right private/public messages, and converts incoming
/// guest commands into engine calls.
class WerewolfServer {
  WerewolfServer({HostServer? server, this.hostName = 'Host'})
      : _server = server ?? HostServer(html: werewolfBrowserHtml);

  final HostServer _server;
  final String hostName;
  final WerewolfEngine engine = WerewolfEngine();

  /// Flutter host plays as this player; not connected over WebSocket.
  static const String hostId = 'host';
  final Map<GuestId, String> _guestToPlayer = {};
  final Map<String, GuestId> _playerToGuest = {};

  final _stateChanges = StreamController<void>.broadcast();
  Stream<void> get onStateChange => _stateChanges.stream;

  StreamSubscription<GuestMessage>? _msgSub;
  StreamSubscription<GuestId>? _leaveSub;

  Future<Uri?> start() async {
    engine.addPlayer(id: hostId, name: hostName, isHost: true);
    final uri = await _server.start();
    _msgSub = _server.onGuestMessage.listen(_onMessage);
    _leaveSub = _server.onGuestLeave.listen(_onLeave);
    _emit();
    return uri;
  }

  Future<void> stop() async {
    await _msgSub?.cancel();
    await _leaveSub?.cancel();
    await _server.stop();
    await _stateChanges.close();
  }

  int get guestCount => _server.guestCount;

  // ---- Host-side actions (called from the Flutter host UI) -------------

  void hostStart() {
    if (!engine.canStart) return;
    engine.start();
    _broadcastPhase();
    _sendRolesPrivately();
    _emit();
  }

  void hostNightAction(String targetId) => _applyNightAction(hostId, targetId);
  void hostDayVote(String? targetId) => _applyDayVote(hostId, targetId);
  void hostHunterShot(String targetId) => _applyHunterShot(hostId, targetId);

  void hostCallTutorialVote() => _openTutorialVote();
  void hostTutorialVote(bool yes) => _submitTutorialVote(hostId, yes);
  void hostDismissTutorial() {
    engine.tutorialVote.markShown();
    _broadcastTutorialState();
    _emit();
  }

  void advanceFromReveal() {
    engine.advanceToDayVote();
    if (engine.phase == WerewolfPhase.gameOver) {
      _broadcastGameOver();
    } else {
      _broadcastPhase();
    }
    _emit();
  }

  // ---- Guest message handling ------------------------------------------

  void _onMessage(GuestMessage msg) {
    final json = msg.asJson;
    final type = json['type'] as String?;
    switch (type) {
      case 'join':
        _handleJoin(msg.from, json);
      case 'night_action':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _applyNightAction(pid, json['targetId'] as String);
      case 'vote':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _applyDayVote(pid, json['targetId'] as String?);
      case 'hunter_shot':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _applyHunterShot(pid, json['targetId'] as String);
      case 'call_tutorial_vote':
        _openTutorialVote();
      case 'tutorial_vote':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _submitTutorialVote(pid, json['yes'] as bool);
    }
  }

  void _onLeave(GuestId guest) {
    final pid = _guestToPlayer.remove(guest);
    if (pid == null) return;
    _playerToGuest.remove(pid);
    engine.removePlayer(pid);
    engine.tutorialVote.removeVoter(pid);
    _broadcastLobby();
    if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) {
      _broadcastTutorialState();
    }
    _emit();
  }

  void _handleJoin(GuestId guest, Map<String, Object?> json) {
    if (engine.phase != WerewolfPhase.lobby) {
      _server.send(guest,
          jsonEncode({'type': 'error', 'message': 'Game already started'}));
      return;
    }
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return;
    final pid = 'g${_guestToPlayer.length + 1}';
    engine.addPlayer(id: pid, name: name);
    _guestToPlayer[guest] = pid;
    _playerToGuest[pid] = guest;
    _server.send(
        guest,
        jsonEncode({
          'type': 'welcome',
          'yourId': pid,
          'yourName': name,
        }));
    _broadcastLobby();
    _broadcastTutorialState();
    _emit();
  }

  void _applyNightAction(String playerId, String targetId) {
    final p = engine.players[playerId];
    if (p == null || !p.alive) return;
    bool ready = false;
    if (p.role == WerewolfRole.werewolf) {
      ready = engine.submitWolfVote(playerId, targetId);
    } else if (p.role == WerewolfRole.seer) {
      ready = engine.submitSeerTarget(playerId, targetId);
    }
    _emit();
    if (ready) {
      engine.resolveNight();
      _sendSeerResultPrivately();
      _broadcastNightResult();
      if (engine.phase == WerewolfPhase.gameOver) {
        _broadcastGameOver();
      } else if (engine.phase == WerewolfPhase.hunterShot) {
        _broadcastHunterPrompt();
      }
      _emit();
    }
  }

  void _applyDayVote(String playerId, String? targetId) {
    final ready = engine.submitDayVote(playerId, targetId);
    _broadcastVoteUpdate();
    _emit();
    if (ready) {
      engine.resolveDay();
      _broadcastDayResult();
      if (engine.phase == WerewolfPhase.gameOver) {
        _broadcastGameOver();
      } else if (engine.phase == WerewolfPhase.hunterShot) {
        _broadcastHunterPrompt();
      } else {
        _broadcastPhase();
      }
      _emit();
    }
  }

  void _applyHunterShot(String playerId, String targetId) {
    final ok = engine.submitHunterShot(playerId, targetId);
    if (!ok) return;
    _broadcastHunterShotResult();
    if (engine.phase == WerewolfPhase.gameOver) {
      _broadcastGameOver();
    } else if (engine.phase == WerewolfPhase.hunterShot) {
      _broadcastHunterPrompt();
    } else {
      _broadcastPhase();
    }
    _emit();
  }

  // ---- Outbound -------------------------------------------------------

  void _broadcastLobby() {
    _server.broadcast(jsonEncode({
      'type': 'lobby',
      'players': engine.players.values
          .map((p) => {'id': p.id, 'name': p.name, 'isHost': p.isHost})
          .toList(),
      'canStart': engine.canStart,
    }));
  }

  // ---- Tutorial vote ---------------------------------------------------

  void _openTutorialVote() {
    if (engine.phase != WerewolfPhase.lobby) return;
    if (engine.tutorialVote.isOpen) return;
    if (engine.tutorialVote.tutorialShown) return;
    engine.tutorialVote.open(engine.players.keys);
    _broadcastTutorialState();
    _emit();
  }

  void _submitTutorialVote(String voterId, bool yes) {
    if (!engine.tutorialVote.isOpen) return;
    engine.tutorialVote.submit(voterId, yes);
    _broadcastTutorialState();
    _emit();
  }

  void _broadcastTutorialState() {
    final v = engine.tutorialVote;
    _server.broadcast(jsonEncode({
      'type': 'tutorial_vote_state',
      'isOpen': v.isOpen,
      'yesCount': v.yesCount,
      'noCount': v.noCount,
      'eligibleCount': v.eligibleCount,
      'result': v.result,
      'tutorialShown': v.tutorialShown,
    }));
  }

  void _sendRolesPrivately() {
    final wolfIds = engine.players.values
        .where((p) => p.role == WerewolfRole.werewolf)
        .map((p) => p.id)
        .toList();
    for (final p in engine.players.values) {
      final payload = jsonEncode({
        'type': 'role',
        'role': p.role!.name,
        if (p.role == WerewolfRole.werewolf) 'wolfIds': wolfIds,
      });
      final guest = _playerToGuest[p.id];
      if (guest != null) _server.send(guest, payload);
    }
  }

  void _sendSeerResultPrivately() {
    final r = engine.lastSeerResult;
    if (r == null) return;
    final guest = _playerToGuest[r.seerId];
    final payload = jsonEncode({
      'type': 'seer_result',
      'targetId': r.targetId,
      'isWerewolf': r.isWerewolf,
    });
    if (guest != null) _server.send(guest, payload);
  }

  void _broadcastPhase() {
    _server.broadcast(jsonEncode({
      'type': 'phase',
      'phase': engine.phase.name,
      'day': engine.day,
      'alive': engine.alive.map(_publicPlayer).toList(),
      'dead': engine.dead.map(_publicPlayer).toList(),
    }));
  }

  void _broadcastVoteUpdate() {
    _server.broadcast(jsonEncode({
      'type': 'vote_update',
      'votes': engine.dayVotes.map((k, v) => MapEntry(k, v ?? '')),
    }));
  }

  void _broadcastNightResult() {
    final n = engine.lastNight!;
    _server.broadcast(jsonEncode({
      'type': 'phase',
      'phase': engine.phase.name,
      'day': engine.day,
      'alive': engine.alive.map(_publicPlayer).toList(),
      'dead': engine.dead.map(_publicPlayer).toList(),
      'killedId': n.killedId,
    }));
  }

  void _broadcastDayResult() {
    final d = engine.lastDay!;
    _server.broadcast(jsonEncode({
      'type': 'day_result',
      'eliminatedId': d.eliminatedId,
      'tally': d.tally,
      'alive': engine.alive.map(_publicPlayer).toList(),
      'dead': engine.dead.map(_publicPlayer).toList(),
      'eliminatedRole': d.eliminatedId == null
          ? null
          : engine.players[d.eliminatedId]!.role!.name,
    }));
  }

  void _broadcastHunterPrompt() {
    _server.broadcast(jsonEncode({
      'type': 'hunter_prompt',
      'hunterId': engine.pendingHunterShooter,
      'alive': engine.alive.map(_publicPlayer).toList(),
      'dead': engine.dead.map(_publicPlayer).toList(),
    }));
  }

  void _broadcastHunterShotResult() {
    final shots = engine.hunterShotsThisRound;
    if (shots.isEmpty) return;
    final last = shots.last;
    _server.broadcast(jsonEncode({
      'type': 'hunter_shot_result',
      'hunterId': last.hunterId,
      'targetId': last.targetId,
      'targetRole': engine.players[last.targetId]!.role!.name,
      'alive': engine.alive.map(_publicPlayer).toList(),
      'dead': engine.dead.map(_publicPlayer).toList(),
    }));
  }

  void _broadcastGameOver() {
    _server.broadcast(jsonEncode({
      'type': 'game_over',
      'winner': engine.winner!.name,
      'roles': {
        for (final p in engine.players.values) p.id: p.role!.name,
      },
    }));
  }

  Map<String, Object?> _publicPlayer(Player p) =>
      {'id': p.id, 'name': p.name, 'alive': p.alive};

  void _emit() => _stateChanges.add(null);
}
