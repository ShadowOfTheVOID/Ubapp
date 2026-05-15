import SwiftUI

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

    var body: some View {
        Group {
            if let client, let game = welcomedGame,
               let yourId = welcomedId, let yourName = welcomedName {
                gameView(client: client, game: game, yourId: yourId, yourName: yourName)
            } else if client != nil {
                connectingView
            } else {
                joinForm
            }
        }
        .navigationTitle("Join a game")
        .onDisappear { client?.close() }
    }

    @ViewBuilder private var joinForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Your name") {
                    TextField("Display name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                GroupBox("Host address") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Join code or IP (e.g. ABCD-EFG)", text: $rawCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        Text("Ask the host for the code shown on their screen, or type the IP shown under the QR.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Connect", action: tryConnect)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || rawCode.trimmingCharacters(in: .whitespaces).isEmpty)
                if !status.isEmpty {
                    Text(status).foregroundStyle(.red).font(.caption)
                }
            }
            .padding()
        }
    }

    @ViewBuilder private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting to \(pendingHost ?? "host")…").foregroundStyle(.secondary)
            if !status.isEmpty { Text(status).foregroundStyle(.red).font(.caption) }
            Button("Cancel") { reset() }.buttonStyle(.bordered)
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
        case "secret_hitler": SecretHitlerGuestView(ctx: ctx)
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
        pendingHost = ip
        let urlString = "ws://\(ip):\(JoinCode.defaultPort)/ws"
        guard let url = URL(string: urlString) else {
            status = "Bad URL: \(urlString)"; return
        }
        let c = GuestClient(url: url)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        c.onStateChange = { s in
            switch s {
            case .open: c.send(["type": "join", "name": trimmedName])
            case .failed(let m): status = "Connection failed: \(m)"
            case .closed: if welcomedGame == nil { status = "Connection closed before joining." }
            default: break
            }
        }
        c.onMessage = { msg in
            // Welcome carries the game key; everything else is queued for the
            // per-game view to replay on first appearance.
            if (msg["type"] as? String) == "welcome",
               let g = msg["game"] as? String,
               let id = msg["yourId"] as? String,
               let nm = msg["yourName"] as? String {
                welcomedGame = g; welcomedId = id; welcomedName = nm
            } else if welcomedGame == nil {
                queuedMessages.append(msg)
            } else {
                // After mount, the per-game view replaces onMessage so this branch
                // shouldn't see messages — but keep them just in case.
                queuedMessages.append(msg)
            }
        }
        c.connect()
        status = ""
        client = c
    }

    private func reset() {
        client?.close()
        client = nil
        welcomedGame = nil; welcomedId = nil; welcomedName = nil
        queuedMessages = []
        status = ""
    }
}

/// Bundle handed to a per-game guest view: the live client, identity, and
/// any messages that arrived between connect and the view mounting.
struct GuestContext {
    let client: GuestClient
    let game: String
    let yourId: String
    let yourName: String
    let replay: [[String: Any]]
}
