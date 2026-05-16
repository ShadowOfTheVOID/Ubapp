import Foundation
import Security

/// WebSocket client used by app guests to join a host phone running the
/// in-app server. Built on `URLSessionWebSocketTask` so there's no extra
/// dependency. JSON is sent/received as text frames — same wire format the
/// browser bundle uses.
@MainActor
final class GuestClient: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    enum State { case connecting, open, closed, failed(String) }

    private(set) var state: State = .connecting
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!

    var onStateChange: ((State) -> Void)?
    /// Each frame received from the server, already decoded as a JSON dict.
    /// Called on the main actor.
    var onMessage: (([String: Any]) -> Void)?

    let url: URL
    init(url: URL) {
        self.url = url
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - TLS: trust the bundled self-signed server cert

    nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if Self.bundledCert.map({ SecTrustSetAnchorCertificates(serverTrust, [$0] as CFArray) == errSecSuccess }) == true {
            SecTrustSetAnchorCertificatesOnly(serverTrust, true)
            var result: SecTrustResultType = .invalid
            SecTrustEvaluate(serverTrust, &result)
            if result == .unspecified || result == .proceed {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private static var bundledCert: SecCertificate? { HostServer.bundledCert }

    func connect() {
        task = session.webSocketTask(with: url)
        task?.resume()
        receiveLoop()
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        update(.closed)
    }

    func send(_ payload: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { [weak self] error in
            guard let self, let error else { return }
            Task { @MainActor in self.update(.failed(error.localizedDescription)) }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let err):
                    self.update(.failed(err.localizedDescription))
                case .success(let msg):
                    if case .string(let s) = msg,
                       let d = s.data(using: .utf8),
                       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self.onMessage?(j)
                    }
                    self.receiveLoop()
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didOpenWithProtocol protocol: String?) {
        Task { @MainActor in self.update(.open) }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                                reason: Data?) {
        Task { @MainActor in self.update(.closed) }
    }

    private func update(_ s: State) { state = s; onStateChange?(s) }
}
