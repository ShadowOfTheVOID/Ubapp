import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BleAdvertiseStatus { idle, starting, advertising, stopped, error, unavailable }

class BleAdvertiseStatusEvent {
  const BleAdvertiseStatusEvent(this.status, {this.error});
  final BleAdvertiseStatus status;
  final String? error;
}

/// Wraps native BLE peripheral advertising. `flutter_blue_plus` is
/// central-only — this fills in the missing piece.
///
/// On Android it talks to BluetoothLeAdvertiser via a MethodChannel.
/// On iOS it talks to CBPeripheralManager the same way.
///
/// The native source files live in `tooling/ble_native/` and must be
/// dropped into the generated platform shells after `flutter create .` —
/// see `tooling/ble_native/README.md` for the one-time install.
abstract class BleAdvertiser {
  static BleAdvertiser? _instance;

  static BleAdvertiser get instance =>
      _instance ??= _PlatformBleAdvertiser();

  /// Replace the singleton with a no-op or fake for tests.
  @visibleForTesting
  static void overrideForTesting(BleAdvertiser fake) => _instance = fake;

  Future<bool> isAvailable();
  Future<bool> requestPermissions();

  /// Begin advertising. Peers scanning for [serviceUuid] will receive scan
  /// results with [peerId] readable as the local-name field.
  Future<void> start({
    required String serviceUuid,
    required String peerId,
  });

  Future<void> stop();

  Stream<BleAdvertiseStatusEvent> get statusStream;
}

class _PlatformBleAdvertiser implements BleAdvertiser {
  static const _method = MethodChannel('ubapp/ble_advertiser');
  static const _events = EventChannel('ubapp/ble_advertiser/events');

  Stream<BleAdvertiseStatusEvent>? _stream;

  @override
  Future<bool> isAvailable() async {
    try {
      return (await _method.invokeMethod<bool>('isAvailable')) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      return (await _method.invokeMethod<bool>('requestPermissions')) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> start({
    required String serviceUuid,
    required String peerId,
  }) async {
    await _method.invokeMethod<void>('start', {
      'serviceUuid': serviceUuid,
      'peerId': peerId,
    });
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  @override
  Stream<BleAdvertiseStatusEvent> get statusStream {
    return _stream ??= _events.receiveBroadcastStream().map((raw) {
      final map = (raw as Map).cast<String, Object?>();
      final s = map['status'] as String? ?? 'error';
      final err = map['error'] as String?;
      return BleAdvertiseStatusEvent(
        BleAdvertiseStatus.values.firstWhere(
          (v) => v.name == s,
          orElse: () => BleAdvertiseStatus.error,
        ),
        error: err,
      );
    });
  }
}

/// No-op advertiser. Used on platforms where the native plugin isn't
/// installed yet (anywhere outside Android/iOS, or before the user copies
/// the tooling sources into their platform shell).
class NoopBleAdvertiser implements BleAdvertiser {
  final _ctrl = StreamController<BleAdvertiseStatusEvent>.broadcast();

  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> requestPermissions() async => false;
  @override
  Future<void> start({required String serviceUuid, required String peerId}) async {
    _ctrl.add(const BleAdvertiseStatusEvent(BleAdvertiseStatus.unavailable));
  }

  @override
  Future<void> stop() async {}
  @override
  Stream<BleAdvertiseStatusEvent> get statusStream => _ctrl.stream;
}

/// 128-bit service UUID used by every Ubapp tag session. All phones in the
/// same round advertise this so scanners can filter to just our peers.
const String kUbappTagServiceUuid = 'e8b3a4e0-aaaa-4123-9876-baddecaf1234';
