import SwiftUI
import UIKit

/// Native screen an app peer sees after joining a Tag host by code via
/// "Join a game". Runs the same `TagSession` (mirror engine + BLE proximity)
/// the host runs, but its transport rides the `GuestLink` socket the join
/// flow already opened. Foreground + screen-on for the round, like the host.
struct TagGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = TagGuestModel()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .center, spacing: 16) {
                        Text("Playing as \(ctx.yourName)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let s = model.state {
                            round(s)
                        } else {
                            ProgressView()
                            Text("Connected. Waiting for the host to begin the round…")
                                .foregroundStyle(.secondary)
                        }
                        Text(model.advertiseStatus)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    Spacer(minLength: 0)
                }
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Tag")
            .onAppear { model.attach(ctx: ctx) }
            .onDisappear { model.dispose() }
        }
        .jamboreeChrome()
    }

    @ViewBuilder
    private func round(_ s: TagState) -> some View {
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
                        Button("Tag") { model.manualTag(p.id) }.buttonStyle(.bordered)
                    }
                    if p.id != model.selfId, !s.isOver, s.variant == .freeze,
                       let me = s.players[model.selfId], me.status == .runner && p.status == .frozen {
                        Button("Unfreeze") { model.manualUnfreeze(p.id) }.buttonStyle(.bordered)
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
final class TagGuestModel: ObservableObject {
    @Published var state: TagState?
    @Published var advertiseStatus: String = "BLE idle."
    private(set) var selfId = ""

    private var session: TagSession?
    private var ble: BleProximityRuntime?
    private var transport: GuestLinkTagTransport?

    func attach(ctx: GuestContext) {
        guard session == nil else { return }
        selfId = ctx.yourId
        let t = GuestLinkTagTransport(client: ctx.client)
        let runtime = BleProximityRuntime(selfPeerId: ctx.yourId)
        runtime.onAdvertiseStatus = { [weak self] s, err in
            self?.advertiseStatus = "BLE: \(s) \(err ?? "")"
        }
        // TagSession.init sets transport.onInbound; subscribe the socket
        // only after, so buffered post-welcome frames aren't lost.
        let sess = TagSession(selfId: ctx.yourId, selfDisplayName: ctx.yourName,
                              proximity: runtime, transport: t)
        sess.onStateChange = { [weak self] s in self?.state = s }
        session = sess; ble = runtime; transport = t
        t.start()
        // Announce ourselves so the host maps our id → display name.
        t.send(.hello(peerId: ctx.yourId, displayName: ctx.yourName))
        UIApplication.shared.isIdleTimerDisabled = true
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

    func dispose() {
        session?.dispose()
        ble?.stop()
        session = nil; ble = nil; transport = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
