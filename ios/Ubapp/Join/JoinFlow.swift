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
    // Temporary on-screen instrumentation for the "stuck on Connecting…"
    // report — no remote logs available on the test device.
    @State private var debugLog: [String] = []
    @State private var connectStarted: Date?

    private func log(_ s: String) {
        let t = connectStarted.map { String(format: "%.1fs", Date().timeIntervalSince($0)) } ?? "—"
        debugLog.append("[\(t)] \(s)")
        if debugLog.count > 40 { debugLog.removeFirst(debugLog.count - 40) }
    }

    var body: some View {
        Group {
            if let client, let game = welcomedGame,
               let yourId = welcomedId, let yourName = welcomedName {
                gameView(client: client, game: game, yourId: yourId, yourName: yourName)
            } else if client != nil {
                connectingView.frame(maxWidth: .infinity, maxHeight: .infinity).ubappChrome()
            } else {
                joinForm.ubappChrome()
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
            ScrollView {
                Text(debugLog.joined(separator: "\n"))
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 260)
            .padding(8)
            .background(Color.black.opacity(0.06))
            .cornerRadius(8)
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
        connectStarted = Date()
        debugLog = []
        let trimmed = rawCode.trimmingCharacters(in: .whitespaces)
        guard let ip = JoinCode.decode(trimmed) else {
            status = "Couldn't read that — enter the 7-character code or the IP."
            return
        }
        log("decode '\(trimmed)' → \(ip)")
        pendingHost = ip
        let urlString = "wss://\(ip):\(JoinCode.defaultPort)/ws"
        guard let url = URL(string: urlString) else {
            status = "Bad URL: \(urlString)"; return
        }
        log("url \(urlString)")
        let c = GuestClient(url: url)
        c.onLog = { m in log("gc: \(m)") }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        c.onStateChange = { s in
            switch s {
            case .connecting: log("state .connecting")
            case .open:
                log(".open — sending join name='\(trimmedName)'")
                c.send(["type": "join", "name": trimmedName])
            case .failed(let m): log(".failed: \(m)"); failBack("Connection failed: \(m)")
            case .closed:
                log(".closed (welcomed=\(welcomedGame != nil))")
                if welcomedGame == nil { failBack("Connection closed before joining.") }
            }
        }
        c.onMessage = { msg in
            let type = (msg["type"] as? String) ?? "?"
            log("recv type=\(type)")
            // Welcome carries the game key; everything else is queued for the
            // per-game view to replay on first appearance.
            if type == "welcome",
               let g = msg["game"] as? String,
               let id = msg["yourId"] as? String,
               let nm = msg["yourName"] as? String {
                log("welcome game=\(g) id=\(id)")
                welcomedGame = g; welcomedId = id; welcomedName = nm
                // Stop consuming here. Everything after `welcome`
                // (lobby/options/phase) now buffers inside the client until
                // the per-game view attaches its handler — closing the
                // hand-off gap that previously dropped those frames.
                c.onMessage = nil
            } else if welcomedGame == nil {
                queuedMessages.append(msg)
            }
        }
        log("connect() resume")
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
