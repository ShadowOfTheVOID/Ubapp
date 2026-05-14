import CoreBluetooth
import Foundation

/// Combined BLE central (scan) + peripheral (advertise) for one tag round.
/// Your phone sees other Ubapp peers AND advertises so others see you.
///
/// Peer id is carried in the advertisement's local name (kCBAdvDataLocalName)
/// and verified against [kUbappTagServiceUuid] on the scan side. iOS limits
/// advertising in the background; this works fine while the app is foreground.
final class BleProximityRuntime: NSObject, ProximitySource {
    enum AdvertiseStatus { case idle, starting, advertising, stopped, error, unavailable }

    let selfPeerId: String
    private let serviceUuid: CBUUID

    var onEvent: ((ProximityEvent) -> Void)?
    var onAdvertiseStatus: ((AdvertiseStatus, String?) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var wantsScan = false
    private var wantsAdvertise = false

    init(selfPeerId: String, serviceUuid: String = kUbappTagServiceUuid) {
        self.selfPeerId = selfPeerId
        self.serviceUuid = CBUUID(string: serviceUuid)
        super.init()
    }

    func start() {
        wantsScan = true; wantsAdvertise = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        if peripheral == nil {
            peripheral = CBPeripheralManager(delegate: self, queue: .main,
                options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
        }
        tryScan(); tryAdvertise()
    }

    func stop() {
        wantsScan = false; wantsAdvertise = false
        central?.stopScan()
        peripheral?.stopAdvertising()
        onAdvertiseStatus?(.stopped, nil)
    }

    private func tryScan() {
        guard wantsScan, let c = central, c.state == .poweredOn else { return }
        c.scanForPeripherals(withServices: [serviceUuid],
                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func tryAdvertise() {
        guard wantsAdvertise, let p = peripheral, p.state == .poweredOn else { return }
        onAdvertiseStatus?(.starting, nil)
        p.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUuid],
            CBAdvertisementDataLocalNameKey: selfPeerId,
        ])
    }
}

extension BleProximityRuntime: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: tryScan()
        case .unsupported, .unauthorized: onAdvertiseStatus?(.unavailable, "scan unavailable")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Peer id: prefer the advertisement's kCBAdvDataLocalName, fall back
        // to the peripheral's name.
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let peerId = (advertisedName ?? peripheral.name ?? "").trimmingCharacters(in: .whitespaces)
        guard !peerId.isEmpty else { return }
        onEvent?(ProximityEvent(
            peerId: peerId, rssi: RSSI.intValue,
            atMs: Int64(Date().timeIntervalSince1970 * 1000)))
    }
}

extension BleProximityRuntime: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn: tryAdvertise()
        case .unsupported, .unauthorized: onAdvertiseStatus?(.unavailable, "advertise unavailable")
        default: onAdvertiseStatus?(.idle, nil)
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if let error { onAdvertiseStatus?(.error, error.localizedDescription) }
        else { onAdvertiseStatus?(.advertising, nil) }
    }
}
