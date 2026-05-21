import SwiftUI

/// Host screen for President. Lobby is host-owned (QR, options, Start).
/// Once the round starts the host plays through the same
/// `PresidentGuestView` everyone else sees, via an in-process loopback,
/// plus a "Next round" / "New game" control the player screen lacks.
struct PresidentView: View {
    @StateObject private var model = PresidentViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                Text("Lobby").font(.headline)
                                TutorialVoteCard(
                                    state: model.tutorialState, tutorial: GameTutorials.president,
                                    onCall: model.callTutorialVote, onVote: model.tutorialVote,
                                    onDismiss: model.dismissTutorial)
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
                VStack(spacing: 0) {
                    PresidentGuestView(ctx: ctx)
                    if model.phase == .gameOver {
                        HStack {
                            Button("Next round") { model.nextRound() }
                                .buttonStyle(.borderedProminent)
                            Button("New game") { model.newGame() }
                                .buttonStyle(.bordered)
                        }.padding()
                    }
                }
            }
        }
        .ubappChrome()
        .navigationTitle("President")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var lobbyView: some View {
        GroupBox("Players (\(model.players.count))") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name)
                    if p.isHost { Text("(host)").foregroundStyle(.secondary).font(.caption) }
                }
            }
        }
        GroupBox("Options") {
            Toggle("Allow President house rules (chat-enforced)", isOn: Binding(
                get: { model.options.allowHouseRules },
                set: { model.applyOptions(PresOptions(allowHouseRules: $0,
                                                     revolution: model.options.revolution)) }))
            Toggle("Revolution: 4-of-a-kind inverts trick (display only)", isOn: Binding(
                get: { model.options.revolution },
                set: { model.applyOptions(PresOptions(allowHouseRules: model.options.allowHouseRules,
                                                     revolution: $0)) }))
        }
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need 4–7 players to start.").foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class PresidentViewModel: ObservableObject {
    private let server = PresidentServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: PresidentPhase = .lobby
    @Published var players: [PresidentPlayer] = []
    @Published var canStart = false
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var options = PresOptions()
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "president",
                                       yourId: PresidentServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func applyOptions(_ o: PresOptions) { server.hostSetOptions(o) }
    func start() { server.hostStart() }
    func nextRound() { server.hostNextRound() }
    func newGame() { server.hostNewGame() }
    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }
    func stop() {
        server.stop(); joinUrl = nil
        loopback = nil; loopbackCtx = nil
    }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = Array(e.players.values).sorted { $0.id < $1.id }
        canStart = e.canStart
        if options != e.options { options = e.options }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
