import SwiftUI

/// Host screen. Lobby is host-owned (QR, "Start round"). Once the round
/// starts the host plays on the same `SecretHitlerGuestView` every guest
/// sees, via an in-process loopback — every per-phase action (nominate, vote,
/// discard, enact, veto, peek, investigate, execute) is already player-driven.
struct SecretHitlerView: View {
    @StateObject private var model = SecretHitlerViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                      onStop: model.stop)
                        Text("Lobby").font(.headline)
                        TutorialVoteCard(
                            state: model.tutorialState,
                            tutorial: GameTutorials.secretHitler,
                            onCall: model.callTutorialVote,
                            onVote: model.tutorialVote,
                            onDismiss: model.dismissTutorial,
                        )
                        lobbyView
                    }
                    .padding()
                }
            } else if let ctx = model.loopbackCtx {
                SecretHitlerGuestView(ctx: ctx)
            }
        }
        .navigationTitle("Secret Hitler")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var lobbyView: some View {
        GroupBox("Players (\(model.players.count))") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name)
                    if p.isHost { Text("(host)").foregroundStyle(.secondary).font(.caption) }
                    Spacer()
                }
            }
        }
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need 5–10 players to start.").foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class SecretHitlerViewModel: ObservableObject {
    private let server = SecretHitlerServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: SecretHitlerPhase = .lobby
    @Published var players: [SecretHitlerPlayer] = []
    @Published var canStart = false
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "secret_hitler",
                                       yourId: SecretHitlerServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func start() { server.hostStart() }
    func stop() {
        server.stop(); joinUrl = nil
        loopback = nil; loopbackCtx = nil
    }

    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = e.seatOrder.compactMap { e.players[$0] }
        canStart = e.canStart
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
