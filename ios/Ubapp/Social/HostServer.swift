import Foundation
import Network
import CryptoKit

/// Identifies one connected guest (browser tab or app instance) for the
/// duration of the connection. Stable across messages from the same socket.
struct GuestId: Hashable {
    let value: String
}

/// One-tap host server. Spins up an HTTP listener on `port` (default 7654) and
/// upgrades requests at `/ws` to WebSocket. Everything else gets the
/// game-supplied landing HTML. Mirrors lib/social/host_server.dart.
///
/// Built on `Network.framework` (plain TCP listener) so there's no third-party
/// dependency. WebSocket upgrade is handled manually — sending the 101 response
/// and framing — so HTTP and WebSocket can coexist on the same port. Each
/// connection gets a stable [GuestId].
///
/// Game adapters consume [onMessage], [send] privately to one guest, or
/// [broadcast] to all. The served HTML can be swapped via [html] before [start].
final class HostServer {
    let port: NWEndpoint.Port
    var html: String

    private var listener: NWListener?
    private var connections: [GuestId: NWConnection] = [:]
    private var nextId = 0
    private let queue = DispatchQueue(label: "ubapp.host.server")

    var onJoin: ((GuestId) -> Void)?
    var onLeave: ((GuestId) -> Void)?
    var onMessage: ((GuestId, String) -> Void)?

    private(set) var hostIp: String?
    private(set) var boundPort: UInt16?

    init(port: UInt16 = 7654, html: String? = nil) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.html = html ?? Self.defaultHtml
    }

    /// Loads a bundled HTML file (e.g. "mafia_browser") from the app
    /// resources. Falls back to a small inline placeholder if missing.
    static func htmlResource(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "html"),
              let s = try? String(contentsOf: url, encoding: .utf8)
        else { return defaultHtml }
        return s
    }

    /// Returns the URL guests should open. nil if no usable IPv4 (Wi-Fi,
    /// Personal Hotspot bridge, or cellular) is available.
    func start() throws -> URL? {
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
        self.hostIp = LocalNetwork.localIPv4()
        self.boundPort = port.rawValue

        guard let ip = hostIp else { return nil }
        return URL(string: "http://\(ip):\(port.rawValue)/")
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else { return }
            if let d = data, let head = String(data: d, encoding: .utf8),
               head.contains("Upgrade: websocket") || head.contains("upgrade: websocket") {
                self.upgradeWebSocket(conn, headers: head)
            } else {
                self.serveHtml(conn)
            }
        }
    }

    private func serveHtml(_ conn: NWConnection) {
        let body = html
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - WebSocket upgrade

    private func upgradeWebSocket(_ conn: NWConnection, headers: String) {
        guard let key = extractWebSocketKey(from: headers),
              let accept = webSocketAccept(for: key) else {
            conn.cancel(); return
        }
        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { conn.cancel(); return }
            let id = GuestId(value: "g\(self.nextId)")
            self.nextId += 1
            self.connections[id] = conn
            self.onJoin?(id)
            self.readFrames(id: id, conn: conn, pending: Data())
        })
    }

    // MARK: - Frame I/O

    private func readFrames(id: GuestId, conn: NWConnection, pending: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                _ = error
                if self.connections.removeValue(forKey: id) != nil { self.onLeave?(id) }
                return
            }
            var buf = pending
            if let data { buf.append(data) }

            while buf.count >= 2 {
                guard let (text, consumed) = self.parseFrame(buf) else { break }
                buf = Data(buf.dropFirst(consumed))
                if let text { self.onMessage?(id, text) }
            }

            if isComplete {
                if self.connections.removeValue(forKey: id) != nil { self.onLeave?(id) }
            } else if self.connections[id] != nil {
                self.readFrames(id: id, conn: conn, pending: buf)
            }
        }
    }

    /// Parses one WebSocket frame from the start of `data` (which must begin at index 0).
    /// Returns `(text?, bytesConsumed)`: text is nil for non-text frames (still consumed).
    /// Returns nil if the frame is incomplete.
    private func parseFrame(_ data: Data) -> (String?, Int)? {
        guard data.count >= 2 else { return nil }
        let b0 = data[0], b1 = data[1]
        let opcode  = b0 & 0x0F
        let masked  = (b1 & 0x80) != 0
        var payloadLen = Int(b1 & 0x7F)
        var headerLen  = 2

        if payloadLen == 126 {
            guard data.count >= 4 else { return nil }
            payloadLen = Int(data[2]) << 8 | Int(data[3])
            headerLen  = 4
        } else if payloadLen == 127 {
            guard data.count >= 10 else { return nil }
            payloadLen = (0..<8).reduce(0) { $0 << 8 | Int(data[2 + $1]) }
            headerLen  = 10
        }

        let maskLen  = masked ? 4 : 0
        let totalLen = headerLen + maskLen + payloadLen
        guard data.count >= totalLen else { return nil }

        guard opcode == 1 else { return (nil, totalLen) }  // skip non-text (close, ping, binary…)

        let maskStart    = headerLen
        let payloadStart = maskStart + maskLen
        var payload = Data(data[payloadStart ..< totalLen])
        if masked {
            let key = [data[maskStart], data[maskStart+1], data[maskStart+2], data[maskStart+3]]
            for i in 0..<payload.count { payload[i] ^= key[i % 4] }
        }
        return (String(data: payload, encoding: .utf8), totalLen)
    }

    func send(to: GuestId, _ payload: String) {
        guard let conn = connections[to],
              let data = payload.data(using: .utf8) else { return }
        conn.send(content: encodeFrame(data), completion: .contentProcessed { _ in })
    }

    private func encodeFrame(_ payload: Data) -> Data {
        var frame = Data()
        frame.append(0x81)  // FIN + text opcode
        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len < 65536 {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((len >> shift) & 0xFF))
            }
        }
        frame.append(contentsOf: payload)
        return frame
    }

    // MARK: - WebSocket handshake helpers

    private func extractWebSocketKey(from headers: String) -> String? {
        for line in headers.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix("sec-websocket-key:") {
                return String(line.dropFirst("sec-websocket-key:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func webSocketAccept(for key: String) -> String? {
        guard let data = (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").data(using: .utf8) else { return nil }
        return Data(Insecure.SHA1.hash(data: data)).base64EncodedString()
    }

    // MARK: - Public API

    func broadcast(_ payload: String) {
        for id in connections.keys { send(to: id, payload) }
    }

    var guestCount: Int { connections.count }
    var guests: [GuestId] { Array(connections.keys) }

    func stop() {
        for conn in connections.values { conn.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    static let defaultHtml = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Ubapp guest</title>
      <style>
        body { font-family: -apple-system, system-ui, sans-serif; background:#0d1117; color:#e6edf3; margin:0; padding:24px; }
        .card { background:#161b22; padding:20px; border-radius:14px; max-width:480px; margin:auto; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>Connected.</h1>
        <p>Waiting for the host to start a game…</p>
      </div>
    </body>
    </html>
    """
}

enum LocalNetwork {
    /// Returns the device's best-candidate IPv4 address for guests to reach.
    /// Walks every up, non-loopback interface and prefers, in order:
    ///   1. Wi-Fi (`en0`)
    ///   2. Personal Hotspot bridge (`bridge*`) — host is sharing cellular
    ///   3. Other Ethernet/USB (`en1`+)
    ///   4. Cellular (`pdp_ip*`) — works for VPN/mesh peers; carrier NAT
    ///      usually blocks direct guests
    /// Skips loopback, AWDL, low-latency Wi-Fi, VPN tunnels and other
    /// virtual interfaces.
    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var best: (priority: Int, addr: String)?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            ptr = cur.pointee.ifa_next
            guard let sa = cur.pointee.ifa_addr else { continue }
            guard sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = cur.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                  (flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            let priority: Int
            if name == "en0" { priority = 0 }
            else if name.hasPrefix("bridge") { priority = 1 }
            else if name.hasPrefix("en") { priority = 2 }
            else if name.hasPrefix("pdp_ip") { priority = 3 }
            else { continue }
            if let b = best, b.priority <= priority { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa,
                              socklen_t(sa.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            best = (priority, String(cString: host))
        }
        return best?.addr
    }
}
