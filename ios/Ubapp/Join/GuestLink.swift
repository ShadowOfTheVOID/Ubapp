import Foundation

/// Transport abstraction shared by every per-game player view. The screen the
/// host sees is now the *same* player view guests see; the only difference is
/// the wire underneath it:
///
/// - `GuestClient` — a real WebSocket to a remote host phone.
/// - `LoopbackGuest` — an in-process pipe straight into the host's own
///   `HostServer`, so the host plays as a normal player on the same screen.
///
/// Both expose just enough for a per-game guest view: a message sink and a
/// way to send JSON commands. JSON is the same line-oriented format the
/// browser bundle uses.
@MainActor
protocol GuestLink: AnyObject {
    var onMessage: (([String: Any]) -> Void)? { get set }
    func send(_ payload: [String: Any])
}

/// In-process `GuestLink` bound to the host's own `HostServer`. The host is
/// added to its game's engine as the `host` player; this pipe carries the
/// exact JSON a remote guest would exchange, so the host renders the
/// identical player screen and acts through the same code path.
///
/// Messages the server emits before the player view mounts (lobby roster,
/// options, the `phase`/`role` burst from "Start round") are buffered and
/// flushed the moment the view attaches its `onMessage` handler — the same
/// guarantee `JoinFlowView` gives remote guests via its replay queue.
@MainActor
final class LoopbackGuest: GuestLink {
    var onMessage: (([String: Any]) -> Void)? {
        didSet { if onMessage != nil { flush() } }
    }

    let guestId: GuestId
    private weak var server: HostServer?
    private var buffer: [[String: Any]] = []

    init(server: HostServer) {
        self.server = server
        // The game server attaches the local guest when it starts (so it can
        // map it to the `host` player); fall back to attaching here.
        self.guestId = server.localGuestId ?? server.attachLocalGuest()
        server.onLocalSend = { [weak self] raw in
            // HostServer may emit from its background queue (remote guest
            // actions) or from the main actor (host taps). Hop to the main
            // actor before touching SwiftUI-observed state.
            guard let d = raw.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { return }
            Task { @MainActor in self?.deliver(j) }
        }
    }

    private func deliver(_ msg: [String: Any]) {
        if onMessage != nil { onMessage?(msg) } else { buffer.append(msg) }
    }

    private func flush() {
        let pending = buffer
        buffer = []
        for m in pending { onMessage?(m) }
    }

    func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else { return }
        server?.injectFromLocal(s)
    }
}
