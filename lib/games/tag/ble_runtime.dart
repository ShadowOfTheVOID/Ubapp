import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../native/ble_advertiser.dart';
import 'ble_proximity.dart';
import 'proximity.dart';

/// Bundles BLE scan (central, via flutter_blue_plus) and BLE advertise
/// (peripheral, via the BleAdvertiser plugin) for one tag round. Both run
/// in parallel — your phone sees others *and* others see you.
class BleProximityRuntime implements ProximitySource {
  BleProximityRuntime({
    required this.selfPeerId,
    String serviceUuid = kUbappTagServiceUuid,
    BleAdvertiser? advertiser,
  })  : _serviceUuid = serviceUuid,
        _advertiser = advertiser ?? BleAdvertiser.instance,
        _scanner = BleProximity(serviceUuid: Guid(serviceUuid));

  final String selfPeerId;
  final String _serviceUuid;
  final BleAdvertiser _advertiser;
  final BleProximity _scanner;

  StreamSubscription<BleAdvertiseStatusEvent>? _statusSub;
  BleAdvertiseStatus _status = BleAdvertiseStatus.idle;
  String? _statusError;

  BleAdvertiseStatus get status => _status;
  String? get statusError => _statusError;

  @override
  Stream<ProximityEvent> get events => _scanner.events;

  /// Surfaces both the advertiser status and (implicitly) scanner errors.
  Stream<BleAdvertiseStatusEvent> get advertiseStatus =>
      _advertiser.statusStream;

  @override
  Future<void> start() async {
    _statusSub ??= _advertiser.statusStream.listen((e) {
      _status = e.status;
      _statusError = e.error;
    });

    // Kick off both sides. Scanner failures don't block advertising and
    // vice versa.
    final scanFuture = _scanner.start();
    final adFuture = _advertiser.start(
      serviceUuid: _serviceUuid,
      peerId: selfPeerId,
    );
    await Future.wait([scanFuture, adFuture]);
  }

  @override
  Future<void> stop() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await Future.wait([_scanner.stop(), _advertiser.stop()]);
  }
}
