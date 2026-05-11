import 'dart:async';
import 'dart:convert';

import '../../social/host_server.dart';
import 'codenames_browser.dart';
import 'codenames_engine.dart';

class CodenamesServer {
  CodenamesServer({HostServer? server, this.hostName = 'Host'})
      : _server = server ?? HostServer(html: codenamesBrowserHtml);

  final HostServer _server;
  final String hostName;
  final CodenamesEngine engine = CodenamesEngine();

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

  // ---- Host actions ----
  void hostJoinTeam(Team team) {
    engine.setTeam(hostId, team);
    _broadcastLobby();
    _sendRolesToAll();
    _emit();
  }

  void hostSetSpymaster(bool on) {
    engine.setSpymaster(hostId, on);
    _broadcastLobby();
    _sendRolesToAll();
    _emit();
  }

  void hostStart() {
    engine.start();
    _broadcastState();
    _sendRolesToAll();
    _emit();
  }

  void hostSubmitClue(String clue, int number) {
    engine.submitClue(hostId, clue, number);
    _broadcastState();
    _emit();
  }

  void hostGuess(int index) {
    engine.guess(hostId, index);
    _broadcastState();
    _emit();
  }

  void hostEndTurn() {
    engine.endTurn(hostId);
    _broadcastState();
    _emit();
  }

  void hostNewGame() {
    engine.reset();
    _server.broadcast(jsonEncode({'type': 'reset'}));
    _broadcastLobby();
    _emit();
  }

  // ---- Inbound ----
  void _onMessage(GuestMessage msg) {
    final j = msg.asJson;
    final pid = _guestToPlayer[msg.from];
    switch (j['type']) {
      case 'join':
        _handleJoin(msg.from, j);
      case 'team':
        if (pid != null) {
          engine.setTeam(pid, Team.values.byName(j['team']! as String));
          _broadcastLobby();
          _sendRolesToAll();
          _emit();
        }
      case 'spymaster':
        if (pid != null) {
          engine.setSpymaster(pid, j['on']! as bool);
          _broadcastLobby();
          _sendRolesToAll();
          _emit();
        }
      case 'clue':
        if (pid != null) {
          engine.submitClue(pid, j['clue']! as String, (j['number']! as num).toInt());
          _broadcastState();
          _emit();
        }
      case 'guess':
        if (pid != null) {
          engine.guess(pid, (j['index']! as num).toInt());
          _broadcastState();
          _emit();
        }
      case 'end_turn':
        if (pid != null) {
          engine.endTurn(pid);
          _broadcastState();
          _emit();
        }
    }
  }

  void _onLeave(GuestId guest) {
    final pid = _guestToPlayer.remove(guest);
    if (pid == null) return;
    _playerToGuest.remove(pid);
    if (engine.phase == CodenamesPhase.lobby) {
      engine.removePlayer(pid);
      _broadcastLobby();
    }
    _emit();
  }

  void _handleJoin(GuestId guest, Map<String, Object?> json) {
    if (engine.phase != CodenamesPhase.lobby) {
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

  // ---- Outbound ----
  void _broadcastLobby() {
    _server.broadcast(jsonEncode({
      'type': 'lobby',
      'players': engine.players.values
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'isHost': p.isHost,
                'team': p.team?.name,
                'isSpymaster': p.isSpymaster,
              })
          .toList(),
      'canStart': engine.canStart,
    }));
  }

  void _broadcastState() {
    final boardPublic = engine.board
        .map((c) => {
              'word': c.word,
              'revealed': c.revealed,
              if (c.revealed) 'kind': c.kind.name,
            })
        .toList();
    _server.broadcast(jsonEncode({
      'type': 'state',
      'phase': engine.phase == CodenamesPhase.playing ? 'playing' : 'gameOver',
      'currentTeam': engine.currentTeam.name,
      'currentClue': engine.currentClue,
      'currentNumber': engine.currentNumber,
      'guessesLeft': engine.guessesLeftThisTurn,
      'redLeft': engine.cardsLeftFor(Team.red),
      'blueLeft': engine.cardsLeftFor(Team.blue),
      'board': boardPublic,
      'winner': engine.winner?.name,
      'endReason': engine.endReason,
      'lastEvent': engine.lastEvent ?? '',
    }));
  }

  void _sendRolesToAll() {
    for (final p in engine.players.values) {
      if (p.id == hostId) continue;
      final guest = _playerToGuest[p.id];
      if (guest == null) continue;
      final payload = <String, Object?>{
        'type': 'role',
        'team': p.team?.name,
        'isSpymaster': p.isSpymaster,
      };
      if (p.isSpymaster && engine.board.isNotEmpty) {
        payload['smView'] = engine.board.map((c) => {'kind': c.kind.name}).toList();
      }
      _server.send(guest, jsonEncode(payload));
    }
  }

  void _emit() => _stateChanges.add(null);
}
