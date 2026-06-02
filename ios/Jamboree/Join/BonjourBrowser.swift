import Foundation
import Network

/// Discovers Jamboree hosts on the local network via Bonjour
/// (`_jamboree._tcp`) so a guest can pick a host *by name* in the join flow
/// instead of typing an IP or app code. Pairs with the advertising side in
/// `HostServer`, which sets `NWListener.service` on `start()`.
///
/// `NWBrowser` finds hosts; `resolve(_:)` turns the chosen one into its mDNS
/// **hostname** (e.g. `Tonys-iPhone.local`) rather than a numeric IP, so the
/// connection URL the guest dials never contains an address. The hostname
/// still resolves to an IP inside the network stack, but no numeric address is
/// ever produced, shown, or stored by the app.
@MainActor
final class BonjourBrowser: ObservableObject {
    struct Host: Identifiable, Equatable {
        /// Service instance name — stable within a single browse session.
        let id: String
        let name: String
        let type: String
        let domain: String
        static func == (a: Host, b: Host) -> Bool { a.id == b.id }
    }

    @Published private(set) var hosts: [Host] = []
    @Published private(set) var browsing = false

    private var browser: NWBrowser?
    /// Held for the duration of a resolve — `NetService` and its delegate must
    /// outlive the async callback.
    private var activeService: NetService?
    private var activeResolver: Resolver?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: HostServer.bonjourType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let mapped: [Host] = results.compactMap { result in
                guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                return Host(id: name, name: name, type: type, domain: domain)
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
        activeService?.stop()
        activeService = nil
        activeResolver = nil
        hosts = []
        browsing = false
    }

    /// Resolves a discovered service to its mDNS `(hostname, port)` — e.g.
    /// `("Tonys-iPhone.local", 7654)`. Calls `failure` if the host vanished or
    /// the resolve times out (5s) so the UI can't hang on a stale entry.
    func resolve(_ host: Host,
                 completion: @MainActor @escaping (_ host: String, _ port: UInt16) -> Void,
                 failure: @MainActor @escaping () -> Void) {
        let service = NetService(domain: host.domain, type: host.type, name: host.name)
        let resolver = Resolver(
            onResolved: { hostName, port in Task { @MainActor in completion(hostName, port) } },
            onFailed: { Task { @MainActor in failure() } }
        )
        service.delegate = resolver
        activeService = service
        activeResolver = resolver
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 5)
    }

    /// `NetService` delegate bridge. Hands back the resolved hostname (trailing
    /// dot stripped so it's URL-usable) and port, or signals failure once.
    private final class Resolver: NSObject, NetServiceDelegate {
        private let onResolved: (String, UInt16) -> Void
        private let onFailed: () -> Void
        private var done = false

        init(onResolved: @escaping (String, UInt16) -> Void, onFailed: @escaping () -> Void) {
            self.onResolved = onResolved
            self.onFailed = onFailed
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            guard !done else { return }
            done = true
            guard let host = sender.hostName, sender.port > 0 else { onFailed(); return }
            let clean = host.hasSuffix(".") ? String(host.dropLast()) : host
            onResolved(clean, UInt16(sender.port))
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
            guard !done else { return }
            done = true
            onFailed()
        }
    }
}
