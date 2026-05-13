import 'dart:async';
import 'dart:convert';

import '../../social/host_server.dart';
import '../../tutorials/tutorial_content.dart';
import 'card.dart';
import 'crazy_eights_browser.dart';
import 'crazy_eights_engine.dart';

class CrazyEightsServer {
  CrazyEightsServer({HostServer? server, this.hostName = 'Host'})
      : _server = server ?? HostServer(html: crazyEightsBrowserHtml);

  final HostServer _server;
  final String hostName;
  final CrazyEightsEngine engine = CrazyEightsEngine();

  static const String hostId = 'host';
  final Map<GuestId, String> _guestToPlayer = {};
  final Map<String, GuestId> _playerToGuest = {};

  StreamSubscription<GuestMessage>? _msgSub;
  StreamSubscription<GuestId>? _leaveSub;
  final _stateChanges = StreamController<void>.broadcast();
  Stream<void> get onStateChange => _stateChanges.stream;

  int get guestCount => _server.guestCount;

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

  // Host actions
  void hostStart() {
    engine.start();
    _broadcastState();
    _sendHandsPrivately();
    _emit();
  }

  String? hostPlay(Card card, {Suit? declaredSuit}) {
    final err = engine.playCard(hostId, card, declaredSuit: declaredSuit);
    if (err == null) {
      _broadcastState();
      _sendHandsPrivately();
      if (engine.phase == CrazyEightsPhase.gameOver) _broadcastOver();
      _emit();
    }
    return err;
  }

  void hostDraw() {
    engine.drawOne(hostId);
    _broadcastState();
    _sendHandsPrivately();
    _emit();
  }

  void hostPass() {
    engine.passAfterDraw(hostId);
    _broadcastState();
    _emit();
  }

  void hostNewGame() {
    engine.reset();
    _server.broadcast(jsonEncode({'type': 'reset'}));
    _broadcastLobby();
    _emit();
  }

  void hostCallTutorialVote() => _openTutorialVote();
  void hostTutorialVote(bool yes) => _submitTutorialVote(hostId, yes);
  void hostDismissTutorial() {
    engine.tutorialVote.markShown();
    _broadcastTutorialState();
    _emit();
  }

  // Inbound
  void _onMessage(GuestMessage msg) {
    final json = msg.asJson;
    switch (json['type']) {
      case 'join':
        _handleJoin(msg.from, json);
      case 'play':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _applyPlay(pid, json);
      case 'draw':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _applyDraw(pid);
      case 'pass':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _applyPass(pid);
      case 'call_tutorial_vote':
        _openTutorialVote();
      case 'tutorial_vote':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _submitTutorialVote(pid, json['yes']! as bool);
    }
  }

  void _onLeave(GuestId guest) {
    final pid = _guestToPlayer.remove(guest);
    if (pid == null) return;
    _playerToGuest.remove(pid);
    if (engine.phase == CrazyEightsPhase.lobby) {
      engine.removePlayer(pid);
      engine.tutorialVote.removeVoter(pid);
      _broadcastLobby();
      if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) {
        _broadcastTutorialState();
      }
    }
    _emit();
  }

  void _handleJoin(GuestId guest, Map<String, Object?> json) {
    if (engine.phase != CrazyEightsPhase.lobby) {
      _server.send(guest,
          jsonEncode({'type': 'error', 'message': 'Game already in progress'}));
      return;
    }
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return;
    final pid = 'g${_guestToPlayer.length + 1}';
    engine.addPlayer(id: pid, name: name);
    _guestToPlayer[guest] = pid;
    _playerToGuest[pid] = guest;
    _server.send(guest,
        jsonEncode({'type': 'welcome', 'yourId': pid, 'yourName': name}));
    _broadcastLobby();
    _broadcastTutorialState();
    _emit();
  }

  void _applyPlay(String pid, Map<String, Object?> json) {
    final card = Card(
      Suit.values.byName(json['suit']! as String),
      json['rank']! as int,
    );
    final declared = json['declaredSuit'] == null
        ? null
        : Suit.values.byName(json['declaredSuit']! as String);
    final err = engine.playCard(pid, card, declaredSuit: declared);
    if (err == null) {
      _broadcastState();
      _sendHandsPrivately();
      if (engine.phase == CrazyEightsPhase.gameOver) _broadcastOver();
      _emit();
    } else {
      final guest = _playerToGuest[pid];
      if (guest != null) {
        _server.send(guest, jsonEncode({'type': 'error', 'message': err}));
      }
    }
  }

  void _applyDraw(String pid) {
    engine.drawOne(pid);
    _broadcastState();
    _sendHandsPrivately();
    _emit();
  }

  void _applyPass(String pid) {
    engine.passAfterDraw(pid);
    _broadcastState();
    _emit();
  }

  // Outbound
  void _broadcastLobby() {
    _server.broadcast(jsonEncode({
      'type': 'lobby',
      'players': engine.players.values
          .map((p) => {'id': p.id, 'name': p.name, 'isHost': p.isHost})
          .toList(),
    }));
  }

  void _broadcastState() {
    final top = engine.topCard;
    _server.broadcast(jsonEncode({
      'type': 'state',
      'currentId': engine.current?.id,
      'topCard': top?.toJson(),
      'activeSuit': engine.activeSuit?.name,
      'drawCount': engine.drawPile.length,
      'justDrew': engine.justDrew,
      'lastEvent': engine.lastEvent ?? '',
      'players': engine.players.values
          .map((p) => {'id': p.id, 'name': p.name, 'handCount': p.hand.length})
          .toList(),
    }));
  }

  void _sendHandsPrivately() {
    for (final p in engine.players.values) {
      if (p.id == hostId) continue;
      final guest = _playerToGuest[p.id];
      if (guest == null) continue;
      _server.send(
          guest,
          jsonEncode({
            'type': 'hand',
            'cards': p.hand.map((c) => c.toJson()).toList(),
          }));
    }
  }

  void _broadcastOver() {
    _server.broadcast(jsonEncode({
      'type': 'over',
      'winnerId': engine.winnerId,
      'players': engine.players.values
          .map((p) => {'id': p.id, 'name': p.name, 'handCount': p.hand.length})
          .toList(),
    }));
  }

  // ---- Tutorial vote ---------------------------------------------------

  void _openTutorialVote() {
    if (engine.phase != CrazyEightsPhase.lobby) return;
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
    final payload = <String, Object?>{
      'type': 'tutorial_vote_state',
      'isOpen': v.isOpen,
      'yesCount': v.yesCount,
      'noCount': v.noCount,
      'eligibleCount': v.eligibleCount,
      'result': v.result,
      'tutorialShown': v.tutorialShown,
    };
    if (v.result == true && !v.tutorialShown) {
      payload['title'] = GameTutorials.crazyEights.title;
      payload['sections'] = GameTutorials.crazyEights.sectionsJson();
      payload['menuSections'] = GameTutorials.crazyEights.browserMenuSectionsJson();
    }
    _server.broadcast(jsonEncode(payload));
  }

  void _emit() => _stateChanges.add(null);
}
