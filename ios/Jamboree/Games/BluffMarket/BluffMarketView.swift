import SwiftUI

/// Host screen for Bluff Market. Lobby is host-owned. After "Start" the
/// host plays through the same `BluffMarketGuestView` everyone else sees,
/// via an in-process loopback, plus "Reveal" + "New game" controls.
struct BluffMarketView: View {
    @StateObject private var model = BluffMarketViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                VStack(spacing: 4) {
                                    MonoLabel("Hosting · Bluff Market", color: JamboreeTheme.accent)
                                    Text("Waiting for players")
                                        .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                        .foregroundStyle(.white)
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                TutorialVoteCard(
                                    state: model.tutorialState, tutorial: GameTutorials.bluffMarket,
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
                    BluffMarketGuestView(ctx: ctx)
                    HStack {
                        if model.phase == .scoring {
                            Button("Reveal final scores") { model.finalize() }
                                .buttonStyle(UbPrimaryButtonStyle()).padding(20)
                        }
                        if model.phase == .gameOver {
                            Button("Rematch · same room") { model.newGame() }
                                .buttonStyle(UbPrimaryButtonStyle()).padding(20)
                        }
                    }
                }
            }
        }
        .jamboreeChrome()
        .navigationTitle("Bluff Market")
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
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: JamboreeRadius.row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Options")
            VStack(spacing: 12) {
                Stepper(value: $model.turnsPerPlayer, in: 2...8) {
                    Text("Turns per player: \(model.turnsPerPlayer)")
                }
                .onChange(of: model.turnsPerPlayer) { _, v in
                    model.applyOptions(BluffMarketOptions(turnsPerPlayer: v,
                                                         twoBombs: model.options.twoBombs,
                                                         wildcard: model.options.wildcard))
                }
                Toggle("Two Bombs (larger groups)", isOn: Binding(
                    get: { model.options.twoBombs },
                    set: { model.applyOptions(BluffMarketOptions(turnsPerPlayer: model.turnsPerPlayer,
                                                                 twoBombs: $0,
                                                                 wildcard: model.options.wildcard)) }))
                Toggle("Include Wildcard", isOn: Binding(
                    get: { model.options.wildcard },
                    set: { model.applyOptions(BluffMarketOptions(turnsPerPlayer: model.turnsPerPlayer,
                                                                 twoBombs: model.options.twoBombs,
                                                                 wildcard: $0)) }))
            }
            .font(.system(size: 15))
            .tint(JamboreeTheme.accent)
            .padding(14)
            .ubCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if model.canStart {
            Button("Start round · \(model.players.count) players") { model.start() }
                .buttonStyle(UbPrimaryButtonStyle())
        } else {
            Text("Need 3–6 players to start.")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
        }
    }
}

@MainActor
final class BluffMarketViewModel: ObservableObject {
    private let server = BluffMarketServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: BluffMarketPhase = .lobby
    @Published var players: [BluffPlayer] = []
    @Published var canStart = false
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var options = BluffMarketOptions()
    @Published var turnsPerPlayer: Int = 5
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
            loopbackCtx = GuestContext(client: lb, game: "bluff_market",
                                       yourId: BluffMarketServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func applyOptions(_ o: BluffMarketOptions) { server.hostSetOptions(o) }
    func start() { server.hostStart() }
    func finalize() { server.hostFinalize() }
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
        if turnsPerPlayer != e.options.turnsPerPlayer { turnsPerPlayer = e.options.turnsPerPlayer }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
