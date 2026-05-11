import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'proximity.dart';

/// Default peer-id extractor. Reads from (in order):
///   1. service data for [serviceUuid] (Android side packs the peer id here)
///   2. advertised local name (iOS side puts it here)
///   3. the platform device name
String? defaultPeerIdFromScan(ScanResult r, Guid serviceUuid) {
  final sd = r.advertisementData.serviceData;
  if (sd.isNotEmpty) {
    final bytes = sd[serviceUuid];
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final s = utf8.decode(bytes, allowMalformed: true).trim();
        if (s.isNotEmpty) return s;
      } catch (_) {}
    }
  }
  final local = r.advertisementData.advName.trim();
  if (local.isNotEmpty && local != 'Unknown') return local;
  final platform = r.device.platformName.trim();
  if (platform.isNotEmpty) return platform;
  return null;
}

/// BLE-backed proximity. Scans for peers advertising [serviceUuid] and emits
/// a [ProximityEvent] for each scan result with its RSSI.
///
/// Peripheral advertising (so this phone is discoverable) is handled by the
/// `BleAdvertiser` plugin in `lib/native/ble_advertiser.dart` — see
/// `BleProximityRuntime` for the combined scan + advertise pair.
class BleProximity implements ProximitySource {
  BleProximity({
    required this.serviceUuid,
    String? Function(ScanResult)? parsePeerId,
  }) : parsePeerId =
            parsePeerId ?? ((r) => defaultPeerIdFromScan(r, serviceUuid));

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
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _ctrl.close();
  }
}
