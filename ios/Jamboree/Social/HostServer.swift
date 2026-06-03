import Foundation
import Network
import CryptoKit
import Security
import UIKit

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
    /// Bonjour service type guests browse for to find hosts by name instead of
    /// IP. Advertised automatically on `start()`; the guest side lives in
    /// `BonjourBrowser`. Keep in sync with the Android `HostServer.SERVICE_TYPE`.
    static let bonjourType = "_jamboree._tcp"

    /// The device's mDNS hostname (e.g. "Tonys-iPhone.local"), resolvable by
    /// browsers on the same LAN. Used to build a QR URL that shows a name
    /// rather than a numeric IP in a browser guest's address bar. nil when the
    /// OS reports nothing usable (e.g. "localhost"), in which case callers fall
    /// back to the numeric IP.
    static var localHostName: String? {
        let raw = ProcessInfo.processInfo.hostName
        guard !raw.isEmpty, raw.lowercased() != "localhost" else { return nil }
        let trimmed = raw.hasSuffix(".") ? String(raw.dropLast()) : raw
        return trimmed.contains(".") ? trimmed : trimmed + ".local"
    }

    let port: NWEndpoint.Port
    var html: String

    /// Display name advertised over Bonjour. Defaults to the device's host
    /// name so a guest sees "Tony's game" rather than an address. An empty
    /// string lets the OS substitute the device name.
    var serviceName: String = AppSettings.currentHostName

    private var listener: NWListener?
    /// Guarded by `connectionsLock`: read/written from the listener queue
    /// (accept/readFrames) and from arbitrary caller threads (broadcast,
    /// send, guests, stop). Swift Dictionary is not thread-safe.
    private var connections: [GuestId: NWConnection] = [:]
    private let connectionsLock = NSLock()
    private var nextId = 0
    private let queue = DispatchQueue(label: "jamboree.host.server")

    private func withConnections<T>(_ body: (inout [GuestId: NWConnection]) -> T) -> T {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }
        return body(&connections)
    }

    var onJoin: ((GuestId) -> Void)?
    var onLeave: ((GuestId) -> Void)?
    var onMessage: ((GuestId, String) -> Void)?

    private(set) var hostIp: String?
    private(set) var boundPort: UInt16?

    /// How long the host app may stay backgrounded before hosting is torn
    /// down. Guests connected over a real socket would otherwise sit in a
    /// dead game while the host is away.
    private let backgroundGrace: TimeInterval = 300
    private var backgroundStopWork: DispatchWorkItem?
    private var lifecycleObservers: [NSObjectProtocol] = []

    /// The host plays as a normal player through an in-process pipe instead
    /// of a TCP socket. When set, `send(to:)`/`broadcast` deliver to this
    /// sink and `injectFromLocal` feeds frames back in as if received.
    private(set) var localGuestId: GuestId?
    var onLocalSend: ((String) -> Void)?

    /// Registers the in-process host guest and returns its stable id.
    func attachLocalGuest() -> GuestId {
        let id = GuestId(value: "local")
        localGuestId = id
        onJoin?(id)
        return id
    }

    func detachLocalGuest() {
        guard let id = localGuestId else { return }
        localGuestId = nil
        onLeave?(id)
    }

    /// Feeds a frame into the server as if the host guest had sent it.
    func injectFromLocal(_ raw: String) {
        guard let id = localGuestId else { return }
        onMessage?(id, raw)
    }

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
        let tls = Self.tlsParameters()
        let listener = try NWListener(using: tls ?? NWParameters.tcp, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        // Advertise over Bonjour so app guests can discover this host by name
        // in the join flow without typing an IP or app code. Tied to the
        // listener's lifecycle — cancelling the listener stops advertising.
        listener.service = NWListener.Service(name: serviceName, type: Self.bonjourType)
        listener.start(queue: queue)
        self.listener = listener
        self.hostIp = LocalNetwork.localIPv4()
        self.boundPort = port.rawValue
        observeAppLifecycle()

        guard let ip = hostIp else { return nil }
        let scheme = tls != nil ? "https" : "http"
        return URL(string: "\(scheme)://\(ip):\(port.rawValue)/")
    }

    // MARK: - TLS

    /// The self-signed certificate extracted from the bundled PKCS12.
    /// Used by both the server (to present) and guest clients (to pin).
    static let bundledCert: SecCertificate? = {
        guard let url = Bundle.main.url(forResource: "jamboree", withExtension: "p12"),
              let data = try? Data(contentsOf: url) else { return nil }
        let opts: [String: Any] = [kSecImportExportPassphrase as String: "jamboree"]
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, opts as CFDictionary, &items) == errSecSuccess,
              let arr = items as? [[String: Any]], let first = arr.first,
              let chain = first[kSecImportItemCertChain as String] as? [SecCertificate] else { return nil }
        return chain.first
    }()

    /// Builds TLS NWParameters using the bundled self-signed PKCS12 identity.
    /// Returns nil (falls back to plain TCP) if the resource is missing.
    private static func tlsParameters() -> NWParameters? {
        guard let url = Bundle.main.url(forResource: "jamboree", withExtension: "p12"),
              let p12Data = try? Data(contentsOf: url) else { return nil }
        let opts: [String: Any] = [kSecImportExportPassphrase as String: "jamboree"]
        var items: CFArray?
        guard SecPKCS12Import(p12Data as CFData, opts as CFDictionary, &items) == errSecSuccess,
              let arr = items as? [[String: Any]], let first = arr.first,
              let identity = first[kSecImportItemIdentity as String] else { return nil }
        let secIdentity = identity as! SecIdentity

        let tlsOpts = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(
            tlsOpts.securityProtocolOptions,
            sec_identity_create(secIdentity)!
        )
        sec_protocol_options_set_peer_authentication_required(
            tlsOpts.securityProtocolOptions, false
        )
        let params = NWParameters(tls: tlsOpts, tcp: NWProtocolTCP.Options())
        return params
    }

    private func dlog(_ s: String) { HostDiagnostics.shared.log(s) }

    // MARK: - App lifecycle

    /// Tears hosting down if the host app stays backgrounded past
    /// `backgroundGrace`. A brief background (notification, glance) is fine —
    /// the timer is cancelled the moment the app returns to the foreground.
    private func observeAppLifecycle() {
        let nc = NotificationCenter.default
        let bg = nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                object: nil, queue: .main) { [weak self] _ in
            self?.scheduleBackgroundStop()
        }
        let fg = nc.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                object: nil, queue: .main) { [weak self] _ in
            self?.cancelBackgroundStop()
        }
        lifecycleObservers = [bg, fg]
    }

    private func scheduleBackgroundStop() {
        cancelBackgroundStop()
        dlog("app backgrounded — will stop hosting in \(Int(backgroundGrace))s if still away")
        let work = DispatchWorkItem { [weak self] in
            self?.dlog("background grace elapsed — stopping hosting")
            self?.stop()
        }
        backgroundStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + backgroundGrace, execute: work)
    }

    private func cancelBackgroundStop() {
        backgroundStopWork?.cancel()
        backgroundStopWork = nil
    }

    private func removeLifecycleObservers() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
    }

    private func accept(_ conn: NWConnection) {
        dlog("accept: new connection")
        conn.start(queue: queue)
        readRequestHead(conn, accumulated: Data())
    }

    /// Reads until the HTTP header block is complete (CRLFCRLF) before
    /// deciding WebSocket-upgrade vs. serve-HTML. A single `receive` can
    /// return only part of the guest's handshake (TLS record / TCP
    /// segmentation), and deciding off that partial read would either serve
    /// HTML to a WebSocket client or drop a handshake whose
    /// `Sec-WebSocket-Key` line hadn't arrived yet — surfacing on the guest
    /// as "Socket is not connected" and an endless "Connecting…".
    private func readRequestHead(_ conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil { conn.cancel(); return }
            var buf = accumulated
            if let data { buf.append(data) }

            if buf.range(of: Data("\r\n\r\n".utf8)) == nil {
                // Headers not finished. Keep reading unless the peer hung up
                // or the request is implausibly large (malformed / not HTTP).
                if isComplete || buf.count > 65536 { conn.cancel(); return }
                self.readRequestHead(conn, accumulated: buf)
                return
            }

            let head = String(decoding: buf, as: UTF8.self)
            let isUpgrade = head.range(of: "upgrade: websocket", options: .caseInsensitive) != nil
            let firstLine = head.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            self.dlog("head complete \(buf.count)B upgrade=\(isUpgrade) — \(firstLine)")
            if isUpgrade {
                self.upgradeWebSocket(conn, headers: head)
            } else {
                self.serveHtml(conn)
            }
        }
    }

    private func serveHtml(_ conn: NWConnection) {
        // If the host owns the ad-free upgrade, suppress ads for the browser
        // guests this host serves by flagging the page before it loads.
        let body = AdManager.isAdFreePersisted
            ? html.replacingOccurrences(of: "</head>",
                                        with: "<script>window.UB_AD_FREE=true</script></head>")
            : html
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
            dlog("upgrade: missing/invalid Sec-WebSocket-Key → cancel")
            conn.cancel(); return
        }
        // Cap concurrent connections so a single client can't open an
        // unbounded number of sockets (each adds a lobby player and triggers
        // an O(N²) roster fan-out).
        if withConnections({ $0.count }) >= Self.maxConnections {
            dlog("upgrade: connection cap (\(Self.maxConnections)) reached → reject")
            conn.cancel(); return
        }
        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error { self.dlog("upgrade: 101 send error \(error) → cancel"); conn.cancel(); return }
            let id = GuestId(value: "g\(self.nextId)")
            self.nextId += 1
            self.withConnections { $0[id] = conn }
            self.dlog("upgrade: 101 sent, \(id.value) joined")
            self.onJoin?(id)
            self.readFrames(id: id, conn: conn, pending: Data())
        })
    }

    // MARK: - Frame I/O

    private func readFrames(id: GuestId, conn: NWConnection, pending: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.dlog("readFrames \(id.value): rx error \(error) → leave")
                if self.withConnections({ $0.removeValue(forKey: id) }) != nil { self.onLeave?(id) }
                return
            }
            var buf = pending
            if let data { buf.append(data) }
            self.dlog("readFrames \(id.value): rx \(data?.count ?? 0)B (buf \(buf.count)B) isComplete=\(isComplete)")

            // Cap the reassembly buffer so a client that streams a frame
            // declaring (or implying) a huge length can't grow this
            // unboundedly. A single complete frame's header + payload fits
            // well within this; anything larger is malformed/hostile.
            if buf.count > Self.maxFramePayload + 16 {
                self.dlog("readFrames \(id.value): buffer over cap (\(buf.count)B) → drop")
                if self.withConnections({ $0.removeValue(forKey: id) }) != nil { self.onLeave?(id) }
                conn.cancel()
                return
            }

            while buf.count >= 2 {
                guard let (text, consumed) = self.parseFrame(buf) else {
                    self.dlog("readFrames \(id.value): partial/short frame, wait for more")
                    break
                }
                buf = Data(buf.dropFirst(consumed))
                if let text {
                    self.dlog("readFrames \(id.value): text \(text.count)B → \(text.prefix(80))")
                    self.onMessage?(id, text)
                } else {
                    self.dlog("readFrames \(id.value): non-text frame consumed \(consumed)B")
                }
            }

            if isComplete {
                if self.withConnections({ $0.removeValue(forKey: id) }) != nil { self.onLeave?(id) }
            } else if self.withConnections({ $0[id] != nil }) {
                self.readFrames(id: id, conn: conn, pending: buf)
            }
        }
    }

    /// Parses one WebSocket frame from the start of `data` (which must begin at index 0).
    /// Returns `(text?, bytesConsumed)`: text is nil for non-text frames (still consumed).
    /// Returns nil if the frame is incomplete.
    /// Largest WebSocket payload the host will accept in one frame. Game
    /// traffic is small JSON; anything larger is malformed or hostile and is
    /// dropped (the connection is then torn down by `readFrames`).
    static let maxFramePayload = 1 << 20  // 1 MiB

    /// Max concurrent guest connections. Same-room games are small; this is a
    /// generous ceiling that caps connection-flood amplification. Keep in sync
    /// with the Android `HostServer.MAX_CONNECTIONS`.
    static let maxConnections = 32

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

        // A 64-bit length with the high bit set decodes to a negative Int
        // (which would pass the `data.count >= totalLen` check below and then
        // trap on the `payloadStart ..< totalLen` slice), and a large positive
        // one would overflow the `totalLen` addition. Both are malformed
        // frames from a hostile client; reject anything past a sane per-frame
        // cap so a single crafted frame can't crash the host. Game frames are
        // small JSON well under this bound.
        guard payloadLen >= 0, payloadLen <= Self.maxFramePayload else { return nil }

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
        if to == localGuestId { onLocalSend?(payload); return }
        guard let conn = withConnections({ $0[to] }) else {
            dlog("send \(to.value): NO connection for id (lost) — \(payload.prefix(60))")
            return
        }
        guard let data = payload.data(using: .utf8) else { return }
        dlog("send \(to.value): \(payload.count)B → \(payload.prefix(60))")
        conn.send(content: encodeFrame(data), completion: .contentProcessed { _ in })
    }

    /// Sends a final payload to one guest, then drops the connection. Used to
    /// reject a client speaking the wrong protocol (e.g. the browser-tier
    /// join handshake hitting Tag) so it fails fast instead of hanging.
    func disconnect(_ id: GuestId, sending farewell: String? = nil) {
        guard let conn = withConnections({ $0.removeValue(forKey: id) }) else { return }
        if let farewell, let data = farewell.data(using: .utf8) {
            conn.send(content: encodeFrame(data), completion: .contentProcessed { _ in
                conn.cancel()
            })
        } else {
            conn.cancel()
        }
        onLeave?(id)
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
        for id in withConnections({ Array($0.keys) }) { send(to: id, payload) }
        if let local = localGuestId { send(to: local, payload) }
    }

    var guestCount: Int { withConnections { $0.count } }
    var guests: [GuestId] { withConnections { Array($0.keys) } }

    /// A WebSocket Close control frame (opcode 0x8) carrying status 1001
    /// ("going away"). Sent to every guest on `stop()` so the kick is a
    /// clean handshake — the browser's `onclose` and the app guest's
    /// `didCloseWith` fire promptly instead of waiting out an abrupt
    /// TCP teardown.
    private func closeFrame() -> Data { Data([0x88, 0x02, 0x03, 0xE9]) }

    func stop() {
        cancelBackgroundStop()
        removeLifecycleObservers()
        let entries = withConnections { conns -> [(GuestId, NWConnection)] in
            let all = Array(conns)
            conns.removeAll()
            return all
        }
        localGuestId = nil
        onLocalSend = nil
        for (id, conn) in entries {
            conn.send(content: closeFrame(), completion: .contentProcessed { _ in
                conn.cancel()
            })
            onLeave?(id)
        }
        listener?.cancel()
        listener = nil
    }

    static let defaultHtml = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Jamboree guest</title>
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
