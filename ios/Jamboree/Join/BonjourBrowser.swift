import Foundation
import Network

/// Discovers Jamboree hosts on the local network via Bonjour
/// (`_jamboree._tcp`) so a guest can pick a host *by name* in the join flow
/// instead of typing an IP or app code. Pairs with the advertising side in
/// `HostServer`, which sets `NWListener.service` on `start()`.
///
/// `NWBrowser` only yields service *names*; the concrete `host:port` is learned
/// lazily in `resolve(_:)` by briefly opening a connection and reading the
/// established remote path — cheaper than holding a resolver open for every
/// host in the list, and we only need the address once the user taps one.
@MainActor
final class BonjourBrowser: ObservableObject {
    struct Host: Identifiable, Equatable {
        /// Service instance name — stable within a single browse session.
        let id: String
        let name: String
        let endpoint: NWEndpoint
        static func == (a: Host, b: Host) -> Bool { a.id == b.id }
    }

    @Published private(set) var hosts: [Host] = []
    @Published private(set) var browsing = false

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: HostServer.bonjourType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let mapped: [Host] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return Host(id: name, name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.hosts = mapped.sorted { $0.name < $1.name } }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:                 self?.browsing = true
                case .failed, .cancelled:    self?.browsing = false
                default:                     break
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        hosts = []
        browsing = false
    }

    /// Resolves a discovered service to a concrete `(host, port)`. Returns nil
    /// on `completion` if the host vanished or the connection never readied
    /// (guarded by a 5s timeout so the UI can't hang on a stale entry).
    func resolve(_ host: Host,
                 completion: @MainActor @escaping (_ host: String, _ port: UInt16) -> Void,
                 failure: @MainActor @escaping () -> Void) {
        let conn = NWConnection(to: host.endpoint, using: .tcp)
        var finished = false
        let done: (String?, UInt16?) -> Void = { resolvedHost, resolvedPort in
            guard !finished else { return }
            finished = true
            conn.cancel()
            Task { @MainActor in
                if let resolvedHost, let resolvedPort { completion(resolvedHost, resolvedPort) }
                else { failure() }
            }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let endpoint = conn.currentPath?.remoteEndpoint,
                   case let .hostPort(h, p) = endpoint {
                    done(Self.ipString(h), p.rawValue)
                } else {
                    done(nil, nil)
                }
            case .failed, .cancelled:
                done(nil, nil)
            default:
                break
            }
        }
        conn.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { done(nil, nil) }
    }

    /// Renders an `NWEndpoint.Host` as a string usable in a URL. Strips the
    /// IPv6 zone suffix (`%en0`) which a `wss://` URL can't carry.
    private static func ipString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let a): return a.debugDescription
        case .ipv6(let a): return a.debugDescription.split(separator: "%").first.map(String.init) ?? a.debugDescription
        case .name(let n, _): return n
        @unknown default: return ""
        }
    }
}
