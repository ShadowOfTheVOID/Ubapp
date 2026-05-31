import Foundation

struct ProximityEvent {
    let peerId: String
    /// dBm. Closer = larger (less negative).
    let rssi: Int
    let atMs: Int64
}

/// Source of nearby-peer events. Production is BLE; tests can swap in
/// [ManualProximity] which lets a UI button publish a fake event.
protocol ProximitySource: AnyObject {
    var onEvent: ((ProximityEvent) -> Void)? { get set }
    func start()
    func stop()
}

/// Sliding-window detector with hysteresis. Holds the last few RSSI readings
/// per peer; fires `onTouch(peerId)` when the average crosses `enterDbm` and
/// the peer isn't currently in immunity.
final class ProximityDetector {
    let onTouch: (String) -> Void
    let windowSize: Int
    let enterDbm: Int
    let exitDbm: Int
    let immunity: TimeInterval

    init(windowSize: Int = 4, enterDbm: Int = -55, exitDbm: Int = -65,
         immunity: TimeInterval = 2, onTouch: @escaping (String) -> Void) {
        self.windowSize = windowSize; self.enterDbm = enterDbm; self.exitDbm = exitDbm
        self.immunity = immunity; self.onTouch = onTouch
    }

    private var windows: [String: [Int]] = [:]
    private var inside: [String: Bool] = [:]
    private var immuneUntil: [String: Date] = [:]

    func grantImmunity(_ peerId: String) {
        immuneUntil[peerId] = Date().addingTimeInterval(immunity)
    }

    func ingest(_ event: ProximityEvent) {
        var w = windows[event.peerId] ?? []
        w.append(event.rssi)
        if w.count > windowSize { w.removeFirst() }
        windows[event.peerId] = w
        let avg = Double(w.reduce(0, +)) / Double(w.count)

        let wasInside = inside[event.peerId] ?? false
        let isInside = wasInside ? avg >= Double(exitDbm) : avg >= Double(enterDbm)
        inside[event.peerId] = isInside

        if !wasInside && isInside {
            if let until = immuneUntil[event.peerId], Date() < until { return }
            onTouch(event.peerId)
        }
    }

    func reset() {
        windows.removeAll(); inside.removeAll(); immuneUntil.removeAll()
    }
}

/// Test source: emits whatever you push into it. Used by the dev "simulate
/// tag" button in the lobby.
final class ManualProximity: ProximitySource {
    var onEvent: ((ProximityEvent) -> Void)?
    func start() {}
    func stop() {}
    func push(peerId: String, rssi: Int = -45) {
        onEvent?(ProximityEvent(
            peerId: peerId, rssi: rssi,
            atMs: Int64(Date().timeIntervalSince1970 * 1000)))
    }
}

/// Stable service UUID used to identify Ubapp tag peers in BLE adverts and scans.
let kUbappTagServiceUuid = "12340000-cafe-1337-1337-deadbeefcafe"
