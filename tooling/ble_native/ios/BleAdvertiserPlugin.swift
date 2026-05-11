import CoreBluetooth
import Flutter
import Foundation

/// Drop this file into ios/Runner/ after running `flutter create .` and
/// register it from AppDelegate. See tooling/ble_native/README.md.
///
/// Wraps CBPeripheralManager. Advertises our service UUID with the peer
/// id encoded as the local name — that's the one field iOS lets apps put
/// arbitrary text in while foregrounded.
///
/// Info.plist requires NSBluetoothAlwaysUsageDescription.
public class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate, FlutterStreamHandler {

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  private var peripheral: CBPeripheralManager?
  private var pendingServiceUuid: String?
  private var pendingPeerId: String?
  private var isAdvertising = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BleAdvertiserPlugin()
    let method = FlutterMethodChannel(name: "ubapp/ble_advertiser", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(name: "ubapp/ble_advertiser/events", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: method)
    events.setStreamHandler(instance)
    instance.methodChannel = method
    instance.eventChannel = events
  }

  // MARK: - Method channel
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(CBCentralManager.authorization == .allowedAlways || CBCentralManager.authorization == .notDetermined)
    case "requestPermissions":
      // Triggers the permission prompt by instantiating the peripheral
      // manager. iOS doesn't have a separate request API.
      ensurePeripheral()
      result(true)
    case "start":
      guard let args = call.arguments as? [String: Any],
            let serviceUuid = args["serviceUuid"] as? String,
            let peerId = args["peerId"] as? String else {
        result(FlutterError(code: "bad_args", message: "serviceUuid and peerId required", details: nil))
        return
      }
      pendingServiceUuid = serviceUuid
      pendingPeerId = peerId
      ensurePeripheral()
      if peripheral?.state == .poweredOn {
        startAdvertising()
      } else {
        emit("starting", error: nil)
      }
      result(nil)
    case "stop":
      stopAdvertising()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Event channel
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - Peripheral manager
  private func ensurePeripheral() {
    if peripheral == nil {
      peripheral = CBPeripheralManager(delegate: self, queue: nil)
    }
  }

  private func startAdvertising() {
    guard let p = peripheral, let uuid = pendingServiceUuid, let peerId = pendingPeerId else { return }
    guard p.state == .poweredOn else {
      emit("starting", error: nil)
      return
    }
    if isAdvertising { p.stopAdvertising() }
    let serviceUuid = CBUUID(string: uuid)
    let data: [String: Any] = [
      CBAdvertisementDataServiceUUIDsKey: [serviceUuid],
      CBAdvertisementDataLocalNameKey: peerId,
    ]
    p.startAdvertising(data)
    isAdvertising = true
  }

  private func stopAdvertising() {
    peripheral?.stopAdvertising()
    isAdvertising = false
    emit("stopped", error: nil)
  }

  // MARK: - CBPeripheralManagerDelegate
  public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    switch peripheral.state {
    case .poweredOn:
      if pendingServiceUuid != nil { startAdvertising() }
    case .poweredOff:
      emit("error", error: "Bluetooth is powered off")
    case .unauthorized:
      emit("error", error: "Bluetooth permission denied")
    case .unsupported:
      emit("unavailable", error: nil)
    case .resetting:
      emit("starting", error: nil)
    case .unknown:
      emit("starting", error: nil)
    @unknown default:
      emit("error", error: "Unknown state")
    }
  }

  public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if let e = error {
      emit("error", error: e.localizedDescription)
    } else {
      emit("advertising", error: nil)
    }
  }

  private func emit(_ status: String, error: String?) {
    eventSink?(["status": status, "error": error as Any])
  }
}
