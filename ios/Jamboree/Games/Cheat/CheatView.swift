import SwiftUI

/// Host screen for Cheat. Lobby is host-owned (QR, options, Start). Once the
/// round starts the host plays through the same `CheatGuestView` everyone
/// else sees, via an in-process loopback, plus a "New game" control the
/// player screen lacks.
struct CheatView: View {
    @StateObject private var model = CheatViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                VStack(spacing: 4) {
                                    MonoLabel("Hosting · Cheat", color: JamboreeTheme.accent)
                                    Text("Waiting for players")
                                        .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                        .foregroundStyle(.white)
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                TutorialVoteCard(
                                    state: model.tutorialState, tutorial: GameTutorials.cheat,
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
                    CheatGuestView(ctx: ctx)
                    if model.phase == .gameOver {
                        Button("Rematch · same room") { model.newGame() }
                            .buttonStyle(UbPrimaryButtonStyle())
                            .padding(20)
                    }
                }
            }
        }
        .jamboreeChrome()
        .navigationTitle("Cheat")
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
                Toggle("Free claim (any rank, no sequence)", isOn: Binding(
                    get: { model.options.freeClaim },
                    set: { var o = model.options; o.freeClaim = $0; model.applyOptions(o) }))
                Toggle("Random starting rank", isOn: Binding(
                    get: { model.options.randomStartRank },
                    set: { var o = model.options; o.randomStartRank = $0; model.applyOptions(o) }))
                    .disabled(model.options.freeClaim)
                Toggle("Count ranks downward", isOn: Binding(
                    get: { model.options.descending },
                    set: { var o = model.options; o.descending = $0; model.applyOptions(o) }))
                    .disabled(model.options.freeClaim)
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
            Text("Need 3–8 players to start.")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
        }
    }
}

@MainActor
final class CheatViewModel: ObservableObject {
    private let server = CheatServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: CheatPhase = .lobby
    @Published var players: [CheatPlayer] = []
    @Published var canStart = false
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var options = CheatOptions()
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "cheat",
                                       yourId: CheatServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func applyOptions(_ o: CheatOptions) { server.hostSetOptions(o) }
    func start() { server.hostStart() }
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
