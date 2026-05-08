import 'dart:async';
import 'dart:convert';

import '../../social/host_server.dart';
import 'imposter_browser.dart';
import 'imposter_engine.dart';

class ImposterServer {
  ImposterServer({HostServer? server, this.hostName = 'Host'})
      : _server = server ?? HostServer(html: imposterBrowserHtml);

  final HostServer _server;
  final String hostName;
  final ImposterEngine engine = ImposterEngine();

  static const String hostId = 'host';
  final Map<GuestId, String> _guestToPlayer = {};
  final Map<String, GuestId> _playerToGuest = {};

  final _stateChanges = StreamController<void>.broadcast();
  Stream<void> get onStateChange => _stateChanges.stream;
  StreamSubscription<GuestMessage>? _msgSub;
  StreamSubscription<GuestId>? _leaveSub;

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

  // Host-side actions
  void hostStart({String? category}) {
    engine.start(categoryName: category);
    _sendRolesPrivately();
    _emit();
  }

  void hostBeginVoting() {
    engine.beginVoting();
    _server.broadcast(jsonEncode({'type': 'voting'}));
    _emit();
  }

  void hostVote(String? targetId) => _applyVote(hostId, targetId);

  void hostNewRound() {
    engine.reset();
    _server.broadcast(jsonEncode({'type': 'reset'}));
    _broadcastLobby();
    _emit();
  }

  // Inbound
  void _onMessage(GuestMessage msg) {
    final json = msg.asJson;
    switch (json['type']) {
      case 'join':
        _handleJoin(msg.from, json);
      case 'vote':
        final pid = _guestToPlayer[msg.from];
        if (pid != null) _applyVote(pid, json['targetId'] as String?);
    }
  }

  void _onLeave(GuestId guest) {
    final pid = _guestToPlayer.remove(guest);
    if (pid == null) return;
    _playerToGuest.remove(pid);
    engine.removePlayer(pid);
    _broadcastLobby();
    _emit();
  }

  void _handleJoin(GuestId guest, Map<String, Object?> json) {
    if (engine.phase != ImposterPhase.lobby) {
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
    _emit();
  }

  void _applyVote(String voterId, String? targetId) {
    final ready = engine.submitVote(voterId, targetId);
    _emit();
    if (ready) {
      engine.resolveVotes();
      _broadcastResult();
      _emit();
    }
  }

  void _broadcastLobby() {
    _server.broadcast(jsonEncode({
      'type': 'lobby',
      'players': engine.players.values
          .map((p) => {'id': p.id, 'name': p.name, 'isHost': p.isHost})
          .toList(),
      'canStart': engine.canStart,
    }));
  }

  void _sendRolesPrivately() {
    for (final p in engine.players.values) {
      final payload = jsonEncode({
        'type': 'role',
        'category': engine.category,
        'isImposter': p.isImposter,
        if (!p.isImposter) 'word': engine.secretWord,
      });
      if (p.id == hostId) continue;
      final guest = _playerToGuest[p.id];
      if (guest != null) _server.send(guest, payload);
    }
  }

  void _broadcastResult() {
    _server.broadcast(jsonEncode({
      'type': 'result',
      'winner': engine.winner!.name,
      'imposterId': engine.imposterId,
      'mostVotedId': engine.mostVotedId,
      'imposterCaught': engine.imposterCaught,
      'word': engine.secretWord,
      'category': engine.category,
      'players': engine.players.values
          .map((p) => {'id': p.id, 'name': p.name, 'isImposter': p.isImposter})
          .toList(),
    }));
  }

  void _emit() => _stateChanges.add(null);
}
