import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'proximity.dart';

/// BLE-backed proximity. Scans for peers advertising [serviceUuid] and emits
/// a [ProximityEvent] for each scan result with its RSSI.
///
/// NOTE: peripheral *advertising* is not handled here — `flutter_blue_plus`
/// is central-only. To make this phone discoverable, plug in an Android
/// peripheral plugin or a small platform channel calling `CBPeripheralManager`
/// on iOS. The game logic doesn't care which side advertises — as long as
/// every phone advertises something with [serviceUuid] and a peer-id payload,
/// scanning here will pick it up.
class BleProximity implements ProximitySource {
  BleProximity({
    required this.serviceUuid,
    required this.parsePeerId,
  });

  final Guid serviceUuid;
  final String? Function(ScanResult) parsePeerId;

  final _ctrl = StreamController<ProximityEvent>.broadcast();
  StreamSubscription<List<ScanResult>>? _sub;

  @override
  Stream<ProximityEvent> get events => _ctrl.stream;

  @override
  Future<void> start() async {
    if (await FlutterBluePlus.isSupported == false) return;
    await FlutterBluePlus.startScan(
      withServices: [serviceUuid],
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    _sub = FlutterBluePlus.scanResults.listen((results) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final r in results) {
        final peerId = parsePeerId(r);
        if (peerId == null) continue;
        _ctrl.add(ProximityEvent(peerId: peerId, rssi: r.rssi, atMs: now));
      }
    });
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await FlutterBluePlus.stopScan();
    await _ctrl.close();
  }
}
