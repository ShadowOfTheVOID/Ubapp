import SwiftUI
import UIKit

/// Tag lobby + round screen. The host phone runs:
///   - `HostServer` (so app peers can connect)
///   - `HostTagTransport` wrapping that server
///   - `BleProximityRuntime` for real proximity events
///   - `TagSession` glueing it all to the engine
///
/// Tag rounds must stay foreground because iOS only honors the local-name
/// field of a BLE advert while the app is in front (`UIApplication.isIdleTimerDisabled`
/// keeps the screen awake for the round's duration).
struct TagLobbyView: View {
    @StateObject private var model = TagLobbyViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.hosting {
                    Text("Tag — BLE proximity").font(.headline)
                    Text("Each phone advertises a BLE beacon and scans for others. Stay within a few metres of another player to tag.")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("Variant", selection: $model.variant) {
                        ForEach(TagVariant.allCases, id: \.self) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(model.variant.tagline).font(.caption).foregroundStyle(.secondary)
                    Button("Start hosting") { model.startHosting() }
                        .buttonStyle(.borderedProminent)
                } else if model.state == nil {
                    HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting)
                    GroupBox("Connected peers (\(model.peers.count + 1))") {
                        HStack { Text("You (host)"); Spacer(); Text("ready").foregroundStyle(.green) }
                        ForEach(model.peers, id: \.self) { name in
                            HStack { Text(name); Spacer() }
                        }
                    }
                    Text(model.advertiseStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Begin round") { model.beginRound() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.peers.isEmpty)
                } else if let s = model.state {
                    roundView(s)
                }
            }
            .padding()
        }
        .navigationTitle("Tag")
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func roundView(_ s: TagState) -> some View {
        GroupBox(s.variant.displayName) {
            Text(s.variant.tagline).font(.caption).foregroundStyle(.secondary)
            if let me = s.players[model.selfId] {
                Text("You are: \(statusLabel(me.status))")
                    .foregroundStyle(color(me.status)).bold()
            }
            if s.isOver {
                Text(s.endReason ?? "Round over").font(.headline)
                if let w = s.winnerId, let p = s.players[w] {
                    Text("Winner: \(p.displayName)").foregroundStyle(.green)
                }
                Button("Back to lobby") { model.stop() }
            }
        }

        GroupBox("Players") {
            ForEach(Array(s.players.values).sorted(by: { $0.id < $1.id }), id: \.id) { p in
                HStack {
                    Text(p.displayName)
                    Spacer()
                    Text(statusLabel(p.status)).foregroundStyle(color(p.status))
                    if p.id != model.selfId, !s.isOver,
                       let me = s.players[model.selfId], me.status == .it && p.status == .runner {
                        Button("Tag") { model.manualTag(p.id) }
                            .buttonStyle(.bordered)
                    }
                    if p.id != model.selfId, !s.isOver,
                       s.variant == .freeze,
                       let me = s.players[model.selfId], me.status == .runner && p.status == .frozen {
                        Button("Unfreeze") { model.manualUnfreeze(p.id) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }

        Text("Manual tag/unfreeze buttons are a fallback for when BLE proximity isn't reliable in the room.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func statusLabel(_ s: PlayerStatus) -> String {
        switch s { case .it: "IT"; case .runner: "runner"
                  case .frozen: "frozen"; case .eliminated: "out" }
    }
    private func color(_ s: PlayerStatus) -> Color {
        switch s { case .it: .red; case .runner: .green
                  case .frozen: .cyan; case .eliminated: .gray }
    }
}

@MainActor
final class TagLobbyViewModel: ObservableObject {
    let selfId = "host"
    private let server = HostServer(html: HostServer.htmlResource(named: "tag_browser"))
    private var transport: HostTagTransport?
    private var ble: BleProximityRuntime?
    private var session: TagSession?

    @Published var hosting = false
    @Published var joinUrl: URL?
    @Published var variant: TagVariant = .classic
    @Published var peers: [String] = []
    @Published var state: TagState?
    @Published var advertiseStatus: String = "BLE idle."

    deinit { stop() }

    func startHosting() {
        do { joinUrl = try server.start() } catch { print("HostServer failed: \(error)") }
        hosting = true
        let t = HostTagTransport(server: server)
        t.onPeerConnected = { [weak self] pid in
            // Treat the WebSocket guest id as a transient name; the peer's
            // Hello message will overwrite with their chosen displayName.
            self?.peers.append(pid)
        }
        t.onPeerDisconnected = { [weak self] pid in self?.peers.removeAll { $0 == pid } }
        transport = t

        // Keep the screen on for the round — BLE peripheral advertising only
        // honors the local-name field while foreground.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func beginRound() {
        guard let t = transport else { return }
        let runtime = BleProximityRuntime(selfPeerId: selfId)
        runtime.onAdvertiseStatus = { [weak self] s, err in
            self?.advertiseStatus = "BLE: \(s) \(err ?? "")"
        }
        ble = runtime
        let sess = TagSession(selfId: selfId, selfDisplayName: "Host",
                              proximity: runtime, transport: t)
        sess.onStateChange = { [weak self] s in self?.state = s }
        var names: [String: String] = [selfId: "Host"]
        for p in peers { names[p] = p }
        sess.startHosting(variant: variant, peerNames: names)
        session = sess
    }

    func manualTag(_ peerId: String) {
        guard let s = session?.engine.state, !s.isOver else { return }
        if session?.engine.applyTag(taggerId: selfId, victimId: peerId) == true {
            session?.transport.send(.tag(taggerId: selfId, victimId: peerId,
                                          timeMs: Int64(Date().timeIntervalSince1970 * 1000)))
            state = session?.engine.state
        }
    }

    func manualUnfreeze(_ peerId: String) {
        guard let s = session?.engine.state, !s.isOver else { return }
        if session?.engine.applyUnfreeze(unfreezerId: selfId, victimId: peerId) == true {
            session?.transport.send(.unfreeze(unfreezerId: selfId, victimId: peerId,
                                              timeMs: Int64(Date().timeIntervalSince1970 * 1000)))
            state = session?.engine.state
        }
    }

    func stop() {
        session?.dispose()
        ble?.stop()
        transport?.dispose()
        session = nil; ble = nil; transport = nil
        hosting = false; peers = []; state = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
