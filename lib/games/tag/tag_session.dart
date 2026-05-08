import 'dart:async';
import 'dart:math';

import 'proximity.dart';
import 'tag_engine.dart';
import 'tag_protocol.dart';
import 'tag_variant.dart';

/// Glue between proximity detection, the engine, and outbound network. The
/// host owns the `start` decision; everyone runs the same engine.
class TagSession {
  TagSession({
    required this.selfId,
    required this.selfDisplayName,
    required this.proximity,
    required this.broadcast,
  }) : engine = TagEngine(selfId: selfId);

  final String selfId;
  final String selfDisplayName;
  final ProximitySource proximity;

  /// Send a message to every peer (your transport implementation).
  final void Function(TagMessage) broadcast;

  final TagEngine engine;
  late final ProximityDetector _detector;
  StreamSubscription<ProximityEvent>? _proxSub;
  Timer? _hotPotatoTimer;

  final _stateChanges = StreamController<TagState>.broadcast();
  Stream<TagState> get onStateChange => _stateChanges.stream;

  Future<void> startHosting({
    required TagVariant variant,
    required Map<String, String> peerNames,
  }) async {
    final ids = peerNames.keys.toList()..shuffle(Random());
    final start = StartMessage(
      variant: variant,
      startingItId: ids.first,
      startTimeMs: DateTime.now().millisecondsSinceEpoch,
      peerIds: ids,
    );
    broadcast(start);
    await _beginRound(start, peerNames);
  }

  Future<void> handleIncoming(TagMessage msg, Map<String, String> peerNames) async {
    switch (msg) {
      case StartMessage():
        await _beginRound(msg, peerNames);
      case TagEvent():
        if (engine.applyTag(msg)) _emit();
      case UnfreezeEvent():
        if (engine.applyUnfreeze(msg)) _emit();
      case EndMessage():
        engine.applyEnd(msg);
        _emit();
        await _shutdownRound();
      case HelloMessage():
        // Hellos are handled by the lobby, not the live session.
        break;
    }
  }

  Future<void> _beginRound(StartMessage start, Map<String, String> peerNames) async {
    engine.start(start, peerNames);
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
        broadcast(msg);
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
        broadcast(msg);
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
        broadcast(end);
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
    await _stateChanges.close();
  }
}
