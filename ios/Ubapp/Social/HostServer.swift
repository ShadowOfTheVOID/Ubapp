import Foundation
import Network

/// Identifies one connected guest (browser tab or app instance) for the
/// duration of the connection. Stable across messages from the same socket.
struct GuestId: Hashable {
    let value: String
}

/// One-tap host server. Spins up an HTTP listener on `port` (default 7654) and
/// upgrades requests at `/ws` to WebSocket. Everything else gets the
/// game-supplied landing HTML. Mirrors lib/social/host_server.dart.
///
/// Built on `Network.framework` (`NWListener` + WebSocket protocol options) so
/// there's no third-party dependency. Each connection gets a stable [GuestId].
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
        let opts = NWProtocolWebSocket.Options()
        opts.autoReplyPing = true
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(opts, at: 0)

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
        // We sniff a single line of the request to decide HTTP-page vs WS.
        // For WS upgrade Network.framework handles framing automatically once
        // the WebSocket protocol option is in the stack — but only if the
        // client speaks WebSocket. For plain HTTP GET / we reply with the HTML.
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else { return }
            if let d = data, let head = String(data: d, encoding: .utf8),
               head.contains("Upgrade: websocket") || head.contains("upgrade: websocket") {
                self.registerSocket(conn)
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

    private func registerSocket(_ conn: NWConnection) {
        let id = GuestId(value: "g\(nextId)")
        nextId += 1
        connections[id] = conn
        onJoin?(id)
        readNext(id: id, conn: conn)
    }

    private func readNext(id: GuestId, conn: NWConnection) {
        conn.receiveMessage { [weak self] data, ctx, _, error in
            guard let self else { return }
            if let error {
                _ = error
                self.connections[id] = nil
                self.onLeave?(id)
                return
            }
            if let data, let text = String(data: data, encoding: .utf8) {
                if let ctx, let meta = ctx.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
                   meta.opcode == .text || meta.opcode == .binary {
                    self.onMessage?(id, text)
                }
            }
            if self.connections[id] != nil { self.readNext(id: id, conn: conn) }
        }
    }

    func send(to: GuestId, _ payload: String) {
        guard let conn = connections[to] else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
        conn.send(content: payload.data(using: .utf8), contentContext: ctx,
                  isComplete: true, completion: .contentProcessed { _ in })
    }

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
