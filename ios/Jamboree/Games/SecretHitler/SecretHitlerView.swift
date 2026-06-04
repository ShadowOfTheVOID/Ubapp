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
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                VStack(spacing: 4) {
                                    MonoLabel("Hosting · Secret Hitler", color: JamboreeTheme.accent)
                                    Text("Waiting for players")
                                        .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                        .foregroundStyle(.white)
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                TutorialVoteCard(
                                    state: model.tutorialState,
                                    tutorial: GameTutorials.secretHitler,
                                    onCall: model.callTutorialVote,
                                    onVote: model.tutorialVote,
                                    onDismiss: model.dismissTutorial,
                                )
                                lobbyView
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
                }
            } else if let ctx = model.loopbackCtx {
                SecretHitlerGuestView(ctx: ctx)
            }
        }
        .jamboreeChrome()
        .navigationTitle("Secret Hitler")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var lobbyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Players · \(model.players.count)")
            VStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        if p.isHost { MonoLabel("host", size: 9, color: JamboreeTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14).ubCard(radius: JamboreeRadius.row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if model.canStart {
            Button("Start round · \(model.players.count) players") { model.start() }
                .buttonStyle(UbPrimaryButtonStyle())
        } else {
            Text("Need 5–10 players to start.")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
        }
    }
}

@MainActor
final class SecretHitlerViewModel: ObservableObject {
    private let server = SecretHitlerServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: SecretHitlerPhase = .lobby
    @Published var players: [SecretHitlerPlayer] = []
    @Published var canStart = false
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() {
        server.onStateChange = { [weak self] in self?.refresh() }
        server.onStopped = { [weak self] in self?.joinUrl = nil }
    }

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
