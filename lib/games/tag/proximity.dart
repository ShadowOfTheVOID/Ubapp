import 'dart:async';

class ProximityEvent {
  ProximityEvent({required this.peerId, required this.rssi, required this.atMs});
  final String peerId;
  final int rssi;
  final int atMs;
}

/// Source of nearby-peer events. Production is BLE; tests can swap in
/// [ManualProximity] which lets a UI button publish a fake event.
abstract class ProximitySource {
  Stream<ProximityEvent> get events;
  Future<void> start();
  Future<void> stop();
}

/// Sliding-window detector with hysteresis. Holds onto the last few RSSI
/// readings per peer; fires `onTouch(peerId)` when the average crosses the
/// enter threshold and the peer isn't currently in immunity.
class ProximityDetector {
  ProximityDetector({
    required this.onTouch,
    this.windowSize = 4,
    this.enterDbm = -55,
    this.exitDbm = -65,
    this.immunity = const Duration(seconds: 2),
  });

  final void Function(String peerId) onTouch;
  final int windowSize;
  final int enterDbm;
  final int exitDbm;
  final Duration immunity;

  final Map<String, List<int>> _windows = {};
  final Map<String, bool> _inside = {};
  final Map<String, DateTime> _immuneUntil = {};

  void grantImmunity(String peerId) {
    _immuneUntil[peerId] = DateTime.now().add(immunity);
  }

  void ingest(ProximityEvent event) {
    final w = _windows.putIfAbsent(event.peerId, () => <int>[]);
    w.add(event.rssi);
    if (w.length > windowSize) w.removeAt(0);
    final avg = w.reduce((a, b) => a + b) / w.length;

    final wasInside = _inside[event.peerId] ?? false;
    final isInside = wasInside ? avg >= exitDbm : avg >= enterDbm;
    _inside[event.peerId] = isInside;

    if (!wasInside && isInside) {
      final until = _immuneUntil[event.peerId];
      if (until != null && DateTime.now().isBefore(until)) return;
      onTouch(event.peerId);
    }
  }

  void reset() {
    _windows.clear();
    _inside.clear();
    _immuneUntil.clear();
  }
}

/// Test source: emits whatever you push into it. Used by the dev "simulate
/// tag" button in the lobby.
class ManualProximity implements ProximitySource {
  final _ctrl = StreamController<ProximityEvent>.broadcast();

  @override
  Stream<ProximityEvent> get events => _ctrl.stream;

  void push(String peerId, {int rssi = -45}) {
    _ctrl.add(ProximityEvent(
      peerId: peerId,
      rssi: rssi,
      atMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    await _ctrl.close();
  }
}
