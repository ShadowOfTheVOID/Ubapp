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

    var onInbound: ((TagMessage) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?

    init(server: HostServer) {
        self.server = server
        server.onJoin = { [weak self] g in self?.onPeerConnected?(g.value) }
        server.onLeave = { [weak self] g in
            if let pid = self?.guestToPeer.removeValue(forKey: g) {
                self?.onPeerDisconnected?(pid)
            }
        }
        server.onMessage = { [weak self] g, raw in
            guard let self else { return }
            guard let msg = try? TagMessage.decode(raw) else {
                // Not a Tag peer — almost certainly the browser-tier
                // "Join a game" flow ({"type":"join"}). Tag is BLE-proximity
                // and has no code-join path, so reject it immediately rather
                // than leaving the guest stuck on "Connecting…".
                let err = #"{"type":"error","message":"This host is running Tag. Tag uses Bluetooth proximity and can’t be joined with a code."}"#
                self.server.disconnect(g, sending: err)
                return
            }
            if case let .hello(peerId, _) = msg { self.guestToPeer[g] = peerId }
            self.onInbound?(msg)
            // Echo non-hello traffic back so other peers see it. Host's
            // own TagSession already applied any state change locally.
            if case .hello = msg { /* don't echo hello */ } else { self.server.broadcast(raw) }
        }
    }

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

/// Local-only transport. Single-device dev mode — messages echo back into
/// [onInbound] so the engine still sees what it sent.
final class LoopbackTagTransport: TagTransport {
    var onInbound: ((TagMessage) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?
    func send(_ msg: TagMessage) { onInbound?(msg) }
    func dispose() {}
}
