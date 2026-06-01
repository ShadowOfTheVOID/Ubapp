import SwiftUI
import UIKit

/// Top-level entry for "Join a game" — the app-installed peer flow. Takes a
/// host address (join code or raw IP), opens a `GuestClient`, waits for the
/// host's first `welcome` (which carries a `game` key), then dispatches to
/// the per-game guest view.
struct JoinFlowView: View {
    @State private var rawCode = ""
    @State private var name = ""
    @State private var client: GuestClient?
    @State private var pendingHost: String?
    @State private var welcomedGame: String?
    @State private var welcomedId: String?
    @State private var welcomedName: String?
    @State private var status: String = ""
    @State private var queuedMessages: [[String: Any]] = []
    @StateObject private var discovery = BonjourBrowser()

    var body: some View {
        Group {
            if let client, let game = welcomedGame,
               let yourId = welcomedId, let yourName = welcomedName {
                gameView(client: client, game: game, yourId: yourId, yourName: yourName)
            } else if client != nil {
                connectingView.frame(maxWidth: .infinity, maxHeight: .infinity).jamboreeChrome()
            } else {
                joinForm.jamboreeChrome()
            }
        }
        .navigationTitle("Join a game")
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; discovery.start() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            discovery.stop()
            client?.close()
        }
    }

    private var canConnect: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !rawCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder private var joinForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Join", color: JamboreeTheme.accent)
                    Text("Enter the app code")
                        .font(.system(size: 30, weight: .heavy)).kerning(-0.9)
                        .foregroundStyle(.white)
                    Text("The host's phone is showing it. Letters and numbers.")
                        .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
                }
                .padding(.bottom, 28)

                MonoLabel("Your name").padding(.bottom, 8)
                TextField("", text: $name,
                          prompt: Text("Display name").foregroundColor(JamboreeTheme.faint))
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 16))
                    .padding(14)
                    .ubCard(radius: JamboreeRadius.button)
                    .padding(.bottom, 16)

                nearbyHosts

                MonoLabel("App code").padding(.bottom, 8)
                TextField("", text: $rawCode,
                          prompt: Text("ABCD-EFG").foregroundColor(JamboreeTheme.faint))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .padding(16)
                    .ubCard(radius: JamboreeRadius.button)

                Text("Or paste the IP shown under the host's QR.")
                    .font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
                    .padding(.top, 8)

                if !status.isEmpty {
                    Text(status).foregroundStyle(JamboreeTheme.accent)
                        .font(.system(size: 13)).padding(.top, 12)
                }

                Button(canConnect ? "Connect" : "Connect — needs name + code", action: tryConnect)
                    .buttonStyle(UbPrimaryButtonStyle())
                    .disabled(!canConnect)
                    .opacity(canConnect ? 1 : 0.6)
                    .padding(.top, 24)
            }
            .padding(20)
        }
    }

    /// Bonjour-discovered hosts — tap one to join by name, no IP or code. Only
    /// shown once at least one host is advertising on the network.
    @ViewBuilder private var nearbyHosts: some View {
        if !discovery.hosts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Nearby hosts")
                ForEach(discovery.hosts) { host in
                    Button { tapDiscovered(host) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi")
                                .font(.system(size: 13))
                                .foregroundStyle(JamboreeTheme.accent)
                            Text(host.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(JamboreeTheme.muted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .ubCard(radius: JamboreeRadius.button)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(JamboreeTheme.accent)
            Text("Connecting to \(pendingHost ?? "host")…").foregroundStyle(JamboreeTheme.muted)
            if !status.isEmpty {
                Text(status).foregroundStyle(JamboreeTheme.accent).font(.system(size: 13))
            }
            Button("Cancel") { reset() }.buttonStyle(UbSecondaryButtonStyle()).frame(maxWidth: 200)
        }
        .padding()
    }

    @ViewBuilder
    private func gameView(client: GuestClient, game: String,
                          yourId: String, yourName: String) -> some View {
        let ctx = GuestContext(client: client, game: game, yourId: yourId,
                               yourName: yourName, replay: queuedMessages)
        switch game {
        case "mafia":         MafiaGuestView(ctx: ctx)
        case "werewolf":      WerewolfGuestView(ctx: ctx)
        case "imposter":      ImposterGuestView(ctx: ctx)
        case "codenames":     CodenamesGuestView(ctx: ctx)
        case "crazy_eights":  CrazyEightsGuestView(ctx: ctx)
        case "cheat":         CheatGuestView(ctx: ctx)
        case "president":     PresidentGuestView(ctx: ctx)
        case "bluff_market":  BluffMarketGuestView(ctx: ctx)
        case "secret_hitler": SecretHitlerGuestView(ctx: ctx)
        case "bureaucrat":    BureaucratGuestView(ctx: ctx)
        case "tag":           TagGuestView(ctx: ctx)
        default:
            VStack {
                Text("Unknown game: \(game)").foregroundStyle(.red)
                Button("Disconnect") { reset() }
            }
        }
    }

    private func tryConnect() {
        let trimmed = rawCode.trimmingCharacters(in: .whitespaces)
        guard let ip = JoinCode.decode(trimmed) else {
            status = "Couldn't read that — enter the 7-character code or the IP."
            return
        }
        openConnection(host: ip, port: JoinCode.defaultPort)
    }

    /// Resolves a Bonjour-discovered host to an address and connects — the
    /// no-IP path. The host name is shown to the user; the address is never
    /// surfaced.
    private func tapDiscovered(_ host: BonjourBrowser.Host) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "Enter your name first."; return
        }
        status = "Connecting to \(host.name)…"
        pendingHost = host.name
        discovery.resolve(host, completion: { addr, port in
            openConnection(host: addr, port: port)
        }, failure: {
            status = "Couldn't reach \(host.name) — it may have stopped hosting."
            pendingHost = nil
        })
    }

    /// Shared connect path for both the typed code/IP and a discovered host.
    /// IPv6 literals are bracketed so the `wss://` URL parses.
    private func openConnection(host: String, port: UInt16) {
        pendingHost = host
        let authority = host.contains(":") ? "[\(host)]" : host
        let urlString = "wss://\(authority):\(port)/ws"
        guard let url = URL(string: urlString) else {
            status = "Bad URL: \(urlString)"; return
        }
        let c = GuestClient(url: url)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        c.onStateChange = { s in
            switch s {
            case .open: c.send(["type": "join", "name": trimmedName])
            case .failed(let m): failBack("Connection failed: \(m)")
            case .closed: if welcomedGame == nil { failBack("Connection closed before joining.") }
            case .connecting: break
            }
        }
        c.onMessage = { msg in
            let type = (msg["type"] as? String) ?? ""
            // Welcome carries the game key; everything else is queued for the
            // per-game view to replay on first appearance.
            if type == "welcome",
               let g = msg["game"] as? String,
               let id = msg["yourId"] as? String,
               let nm = msg["yourName"] as? String {
                welcomedGame = g; welcomedId = id; welcomedName = nm
                // Stop consuming here. Everything after `welcome`
                // (lobby/options/phase) now buffers inside the client until
                // the per-game view attaches its handler — closing the
                // hand-off gap that previously dropped those frames.
                c.onMessage = nil
            } else if welcomedGame == nil {
                // A host that rejects this client before any welcome (e.g.
                // Tag, which speaks its own proximity protocol) sends an
                // `error`. Surface it and return to the form instead of
                // hanging on the spinner forever.
                if type == "error" {
                    let m = (msg["message"] as? String) ?? "Host refused the connection."
                    failBack(m)
                } else {
                    queuedMessages.append(msg)
                }
            }
        }
        c.connect()
        status = ""
        client = c
    }

    private func reset() { failBack("") }

    /// Drop the live client and return to the join form, surfacing `message`
    /// (empty for a plain cancel). Guarded on `client` so the re-entrant
    /// `.closed` that `GuestClient.close()` emits is a no-op instead of
    /// recursing — and so a later `.closed` can't overwrite a `.failed`
    /// message with the generic one.
    private func failBack(_ message: String) {
        guard let live = client else { return }
        client = nil
        pendingHost = nil
        welcomedGame = nil; welcomedId = nil; welcomedName = nil
        queuedMessages = []
        status = message
        live.close()
    }
}

/// Bundle handed to a per-game guest view: the live client, identity, and
/// any messages that arrived between connect and the view mounting.
struct GuestContext {
    let client: any GuestLink
    let game: String
    let yourId: String
    let yourName: String
    let replay: [[String: Any]]
}
