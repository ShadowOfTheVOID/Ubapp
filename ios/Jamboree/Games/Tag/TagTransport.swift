import Foundation

/// Bidirectional channel for tag messages. The host wraps its in-app
/// `HostServer` (fan-out to all connected app peers). Each peer wraps a
/// single outbound WebSocket to the host.
protocol TagTransport: AnyObject {
    var onInbound: ((TagMessage) -> Void)? { get set }
    var onPeerConnected: ((String) -> Void)? { get set }
    var onPeerDisconnected: ((String) -> Void)? { get set }
    func send(_ msg: TagMessage)
    func dispose()
}

/// Host-side: wraps a running [HostServer]. Inbound guest messages are
/// parsed as TagMessages; `send` broadcasts to every connected guest. Owns
/// the server — `dispose()` stops it.
final class HostTagTransport: TagTransport {
    private let server: HostServer
    private var guestToPeer: [GuestId: String] = [:]
    /// peerId → chosen display name, learned from the join handshake and the
    /// peer's `hello`. The lobby uses this so peers show their real name.
    private(set) var peerDisplayNames: [String: String] = [:]

    var onInbound: ((TagMessage) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?

    init(server: HostServer) {
        self.server = server
        server.onJoin = { [weak self] g in self?.onPeerConnected?(g.value) }
        server.onLeave = { [weak self] g in
            guard let self else { return }
            if let pid = self.guestToPeer.removeValue(forKey: g) {
                self.peerDisplayNames[pid] = nil
                self.onPeerDisconnected?(pid)
            }
        }
        server.onMessage = { [weak self] g, raw in
            guard let self else { return }
            if let msg = try? TagMessage.decode(raw) {
                if case let .hello(peerId, displayName) = msg {
                    self.guestToPeer[g] = peerId
                    self.peerDisplayNames[peerId] = displayName
                }
                self.onInbound?(msg)
                // Echo non-hello traffic back so other peers see it. Host's
                // own TagSession already applied any state change locally.
                if case .hello = msg { /* don't echo hello */ } else { self.server.broadcast(raw) }
                return
            }
            // Not a TagMessage — the browser-tier "Join a game" handshake.
            // App peers join Tag by code: complete the handshake so the
            // generic flow can mount the native Tag peer view, then the
            // peer speaks TagMessages over this same socket.
            guard let data = raw.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (j["type"] as? String) == "join" else {
                let err = #"{"type":"error","message":"This host is running Tag — open it in the app to join."}"#
                self.server.disconnect(g, sending: err)
                return
            }
            let name = (j["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let peerId = g.value
            self.guestToPeer[g] = peerId
            self.peerDisplayNames[peerId] = name.isEmpty ? peerId : name
            let welcome: [String: Any] = ["type": "welcome", "game": "tag",
                                          "yourId": peerId, "yourName": name]
            if let d = try? JSONSerialization.data(withJSONObject: welcome),
               let s = String(data: d, encoding: .utf8) {
                self.server.send(to: g, s)
            }
        }
    }

    func displayName(for peerId: String) -> String { peerDisplayNames[peerId] ?? peerId }

    func send(_ msg: TagMessage) { server.broadcast(msg.encode()) }
    func dispose() { server.stop() }
}

/// Peer-side: connects one WebSocket to the host. Outbound goes to the host,
/// which fans out to all peers (including us).
final class PeerTagTransport: NSObject, TagTransport, URLSessionWebSocketDelegate, URLSessionDelegate {
    var onInbound: ((TagMessage) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    /// Connects to wss://<host>:<port>/ws derived from the host URL.
    init(serverUrl: URL) {
        super.init()
        var comps = URLComponents(url: serverUrl, resolvingAgainstBaseURL: false)!
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.path = "/ws"
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: comps.url!)
        self.task = task
        task.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let s)):
                if let m = try? TagMessage.decode(s) { self.onInbound?(m) }
                self.receive()
            case .success(.data(let d)):
                if let s = String(data: d, encoding: .utf8),
                   let m = try? TagMessage.decode(s) { self.onInbound?(m) }
                self.receive()
            case .success:
                self.receive()
            case .failure: break
            }
        }
    }

    func send(_ msg: TagMessage) {
        task?.send(.string(msg.encode())) { _ in }
    }

    func dispose() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let cert = HostServer.bundledCert,
              SecTrustSetAnchorCertificates(serverTrust, [cert] as CFArray) == errSecSuccess else {
            completionHandler(.performDefaultHandling, nil); return
        }
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        var result: SecTrustResultType = .invalid
        SecTrustEvaluate(serverTrust, &result)
        if result == .unspecified || result == .proceed {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

/// App-peer transport that rides the browser-tier `GuestLink` socket the
/// generic "Join a game" flow already opened (TLS-pinned, cert handled),
/// rather than dialing a second raw WebSocket. Tag messages travel as the
/// same JSON dicts every other game uses.
final class GuestLinkTagTransport: TagTransport {
    var onInbound: ((TagMessage) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?
    private let client: any GuestLink

    init(client: any GuestLink) { self.client = client }

    /// Subscribe to the socket. Call this *after* the owning `TagSession`
    /// has set `onInbound`, because assigning `GuestClient.onMessage`
    /// synchronously flushes any frames buffered since `welcome` — if we
    /// subscribed in `init` those would arrive before the session is wired.
    @MainActor
    func start() {
        client.onMessage = { [weak self] j in
            guard let self, let m = try? TagMessage.decode(j) else { return }
            self.onInbound?(m)
        }
    }

    func send(_ msg: TagMessage) {
        let payload = msg.jsonObject()
        Task { @MainActor in self.client.send(payload) }
    }

    func dispose() { Task { @MainActor in self.client.onMessage = nil } }
}

/// Local-only transport. Single-device dev mode — messages echo back into
/// [onInbound] so the engine still sees what it sent.
final class LoopbackTagTransport: TagTransport {
    var onInbound: ((TagMessage) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?
    func send(_ msg: TagMessage) { onInbound?(msg) }
    func dispose() {}
}
