import SwiftUI

/// Host's player UI for Crazy Eights. Shows the host's hand along the
/// bottom, the discard / draw piles in the middle, and a suit-declaration
/// sheet when playing an 8.
/// Host screen. Lobby is host-owned (QR, options, "Start round"). Once the
/// round starts the host plays on the same `CrazyEightsGuestView` every guest
/// sees, via an in-process loopback, plus a "New game" control the player
/// screen lacks.
struct CrazyEightsView: View {
    @StateObject private var model = CrazyEightsViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                VStack(spacing: 4) {
                                    MonoLabel("Hosting · Crazy 8s", color: UbappTheme.accent)
                                    Text("Waiting for players")
                                        .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                        .foregroundStyle(.white)
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                TutorialVoteCard(
                                    state: model.tutorialState, tutorial: GameTutorials.crazyEights,
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
                    CrazyEightsGuestView(ctx: ctx)
                    if model.phase == .gameOver {
                        Button("Rematch · same room") { model.newGame() }
                            .buttonStyle(UbPrimaryButtonStyle())
                            .padding(20)
                    }
                }
            }
        }
        .ubappChrome()
        .navigationTitle("Crazy Eights")
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
                        if p.isHost { MonoLabel("host", size: 9, color: UbappTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Options")
            VStack(spacing: 12) {
                Toggle("Custom starting hand", isOn: $model.customHandSize)
                    .onChange(of: model.customHandSize) { _, on in
                        var o = model.options; o.startingHandSize = on ? model.handSizeValue : nil
                        model.applyOptions(o)
                    }
                if model.customHandSize {
                    Stepper(value: $model.handSizeValue, in: 3...10) {
                        Text("Starting hand: \(model.handSizeValue)")
                    }
                    .onChange(of: model.handSizeValue) { _, v in
                        var o = model.options; o.startingHandSize = v
                        model.applyOptions(o)
                    }
                }
                Toggle("Jacks skip next player", isOn: Binding(
                    get: { model.options.jackSkips },
                    set: { var o = model.options; o.jackSkips = $0; model.applyOptions(o) }))
                Toggle("Queens reverse direction", isOn: Binding(
                    get: { model.options.queenReverses },
                    set: { var o = model.options; o.queenReverses = $0; model.applyOptions(o) }))
                Toggle("Twos: next player draws two", isOn: Binding(
                    get: { model.options.twosDrawTwo },
                    set: { var o = model.options; o.twosDrawTwo = $0; model.applyOptions(o) }))
            }
            .font(.system(size: 15))
            .tint(UbappTheme.accent)
            .padding(14)
            .ubCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if model.canStart {
            Button("Start round · \(model.players.count) players") { model.start() }
                .buttonStyle(UbPrimaryButtonStyle())
        } else {
            Text("Need 2–8 players to start.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
    }

}

@MainActor
final class CrazyEightsViewModel: ObservableObject {
    private let server = CrazyEightsServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: CrazyEightsPhase = .lobby
    @Published var players: [CrazyEightsPlayer] = []
    @Published var canStart = false
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var options = CrazyEightsOptions()
    @Published var customHandSize = false
    @Published var handSizeValue = 5
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "crazy_eights",
                                       yourId: CrazyEightsServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func applyOptions(_ o: CrazyEightsOptions) { server.hostSetOptions(o) }
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
        customHandSize = e.options.startingHandSize != nil
        if let s = e.options.startingHandSize, handSizeValue != s { handSizeValue = s }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
