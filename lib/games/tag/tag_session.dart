import 'dart:async';
import 'dart:math';

import 'proximity.dart';
import 'tag_engine.dart';
import 'tag_protocol.dart';
import 'tag_transport.dart';
import 'tag_variant.dart';

/// Glue between proximity detection, the engine, and the network. Owns a
/// [TagTransport] so the host's authoritative engine and every peer's
/// mirror engine apply the same ordered events.
class TagSession {
  TagSession({
    required this.selfId,
    required this.selfDisplayName,
    required this.proximity,
    required this.transport,
  }) : engine = TagEngine(selfId: selfId) {
    _transportSub = transport.inbound.listen(_handleIncoming);
  }

  final String selfId;
  final String selfDisplayName;
  final ProximitySource proximity;
  final TagTransport transport;

  final TagEngine engine;
  Map<String, String> _peerNames = {};

  late final ProximityDetector _detector;
  late final StreamSubscription<TagMessage> _transportSub;
  StreamSubscription<ProximityEvent>? _proxSub;
  Timer? _hotPotatoTimer;

  final _stateChanges = StreamController<TagState>.broadcast();
  Stream<TagState> get onStateChange => _stateChanges.stream;

  /// Host: pick the starting "it", broadcast Start, kick off the round.
  Future<void> startHosting({
    required TagVariant variant,
    required Map<String, String> peerNames,
  }) async {
    _peerNames = Map.of(peerNames);
    final ids = _peerNames.keys.toList()..shuffle(Random());
    final start = StartMessage(
      variant: variant,
      startingItId: ids.first,
      startTimeMs: DateTime.now().millisecondsSinceEpoch,
      peerIds: ids,
      peerNames: _peerNames,
    );
    transport.send(start);
    await _beginRound(start);
  }

  Future<void> _handleIncoming(TagMessage msg) async {
    switch (msg) {
      case StartMessage():
        if (engine.state != null) return; // already running
        _peerNames = Map.of(msg.peerNames);
        await _beginRound(msg);
      case TagEvent():
        if (engine.applyTag(msg)) _emit();
      case UnfreezeEvent():
        if (engine.applyUnfreeze(msg)) _emit();
      case EndMessage():
        engine.applyEnd(msg);
        _emit();
        await _shutdownRound();
      case HelloMessage():
      case TutorialVoteCast():
      case TutorialVoteStateMessage():
      case TutorialVoteCallMessage():
        // Lobby-only — surfaced to the lobby UI via transport directly.
        break;
    }
  }

  Future<void> _beginRound(StartMessage start) async {
    engine.start(start, _peerNames);
    _detector = ProximityDetector(onTouch: _onProximityTouch);
    await proximity.start();
    _proxSub = proximity.events.listen(_detector.ingest);
    _emit();

    if (start.variant == TagVariant.hotPotato) {
      _restartHotPotatoTimer(start.variant.duration);
    }
  }

  void _onProximityTouch(String peerId) {
    final state = engine.state;
    if (state == null || state.isOver) return;
    final me = state.players[selfId];
    final other = state.players[peerId];
    if (me == null || other == null) return;

    if (me.status == PlayerStatus.it && other.status == PlayerStatus.runner) {
      final msg = TagEvent(
        taggerId: selfId,
        victimId: peerId,
        timeMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (engine.applyTag(msg)) {
        transport.send(msg);
        _detector.grantImmunity(peerId);
        _emit();
        if (state.variant == TagVariant.hotPotato) {
          _restartHotPotatoTimer(state.variant.duration);
        }
      }
    } else if (state.variant == TagVariant.freeze &&
        me.status == PlayerStatus.runner &&
        other.status == PlayerStatus.frozen) {
      final msg = UnfreezeEvent(
        unfreezerId: selfId,
        victimId: peerId,
        timeMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (engine.applyUnfreeze(msg)) {
        transport.send(msg);
        _detector.grantImmunity(peerId);
        _emit();
      }
    }
  }

  void _restartHotPotatoTimer(Duration d) {
    _hotPotatoTimer?.cancel();
    _hotPotatoTimer = Timer(d, () {
      final end = engine.hotPotatoTimeout();
      if (end != null) {
        transport.send(end);
        _emit();
      }
    });
  }

  void _emit() {
    final s = engine.state;
    if (s != null) _stateChanges.add(s);
  }

  Future<void> _shutdownRound() async {
    _hotPotatoTimer?.cancel();
    await _proxSub?.cancel();
    _proxSub = null;
    await proximity.stop();
  }

  Future<void> dispose() async {
    await _shutdownRound();
    await _transportSub.cancel();
    await transport.dispose();
    await _stateChanges.close();
  }
}
