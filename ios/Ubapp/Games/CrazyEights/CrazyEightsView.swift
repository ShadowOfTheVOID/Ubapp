import SwiftUI

/// Host's player UI for Crazy Eights. Shows the host's hand along the
/// bottom, the discard / draw piles in the middle, and a suit-declaration
/// sheet when playing an 8.
struct CrazyEightsView: View {
    @StateObject private var model = CrazyEightsViewModel()
    @State private var pendingEight: Card?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                              onStop: model.stop)

                Text(phaseLabel).font(.headline)

                switch model.phase {
                case .lobby:
                    TutorialVoteCard(
                        state: model.tutorialState, tutorial: GameTutorials.crazyEights,
                        onCall: model.callTutorialVote, onVote: model.tutorialVote,
                        onDismiss: model.dismissTutorial)
                    lobbyView
                case .playing: playingView
                case .gameOver: gameOverView
                }
            }
            .padding()
        }
        .navigationTitle("Crazy Eights")
        .onDisappear { model.stop() }
        .confirmationDialog("Declare suit", isPresented: Binding(
            get: { pendingEight != nil }, set: { if !$0 { pendingEight = nil } })) {
            ForEach(Suit.allCases, id: \.self) { s in
                Button("\(s.glyph) \(s.rawValue.capitalized)") {
                    if let card = pendingEight { model.play(card, declaredSuit: s) }
                    pendingEight = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingEight = nil }
        }
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
            Toggle("Custom starting hand", isOn: $model.customHandSize)
                .onChange(of: model.customHandSize) { _, on in
                    model.applyOptions(CrazyEightsOptions(
                        startingHandSize: on ? model.handSizeValue : nil,
                        jackSkips: model.options.jackSkips,
                        queenReverses: model.options.queenReverses))
                }
            if model.customHandSize {
                Stepper(value: $model.handSizeValue, in: 3...10) {
                    Text("Starting hand: \(model.handSizeValue)")
                }
                .onChange(of: model.handSizeValue) { _, v in
                    model.applyOptions(CrazyEightsOptions(
                        startingHandSize: v,
                        jackSkips: model.options.jackSkips,
                        queenReverses: model.options.queenReverses))
                }
            }
            Toggle("Jacks skip next player", isOn: Binding(
                get: { model.options.jackSkips },
                set: { model.applyOptions(CrazyEightsOptions(
                    startingHandSize: model.customHandSize ? model.handSizeValue : nil,
                    jackSkips: $0,
                    queenReverses: model.options.queenReverses)) }))
            Toggle("Queens reverse direction", isOn: Binding(
                get: { model.options.queenReverses },
                set: { model.applyOptions(CrazyEightsOptions(
                    startingHandSize: model.customHandSize ? model.handSizeValue : nil,
                    jackSkips: model.options.jackSkips,
                    queenReverses: $0)) }))
        }
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need 2–8 players to start.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var playingView: some View {
        GroupBox {
            HStack {
                if let top = model.topCard {
                    cardChip(top, faded: false)
                }
                VStack(alignment: .leading) {
                    Text("Active: \(model.activeSuit?.glyph ?? model.topCard?.suit.glyph ?? "—")")
                    Text("Turn: \(model.currentName)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.draw() } label: {
                    VStack { Text("Draw"); Text("(\(model.drawCount))").font(.caption2) }
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!model.hostIsCurrent)
            }
        }
        if let e = model.lastEvent { Text(e).font(.caption).foregroundStyle(.secondary) }

        if model.justDrew, model.hostIsCurrent {
            Button("Pass") { model.pass() }.buttonStyle(.bordered)
        }

        GroupBox("Your hand (\(model.hostHand.count))") {
            let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(model.hostHand.indices, id: \.self) { i in
                    let c = model.hostHand[i]
                    let playable = model.hostIsCurrent && model.canPlay(c)
                    Button {
                        if c.rank == 8 { pendingEight = c }
                        else { model.play(c, declaredSuit: nil) }
                    } label: {
                        cardChip(c, faded: !playable)
                    }
                    .buttonStyle(.plain)
                    .disabled(!playable)
                }
            }
        }
    }

    @ViewBuilder private var gameOverView: some View {
        GroupBox("Result") {
            Text(model.winnerLabel).font(.title2.bold())
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name); Spacer()
                    Text("\(p.hand.count) cards left").foregroundStyle(.secondary)
                }
            }
        }
        Button("New game") { model.newGame() }.buttonStyle(.borderedProminent)
    }

    private func cardChip(_ c: Card, faded: Bool) -> some View {
        VStack(spacing: 2) {
            Text(c.rankShort).font(.headline.bold())
            Text(c.suit.glyph).font(.title3)
        }
        .frame(width: 48, height: 64)
        .background(.white)
        .foregroundStyle(c.suit.isRed ? .red : .black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.3)))
        .opacity(faded ? 0.4 : 1)
    }

    private var phaseLabel: String {
        switch model.phase {
        case .lobby: "Lobby"; case .playing: "Playing"; case .gameOver: "Game over"
        }
    }
}

@MainActor
final class CrazyEightsViewModel: ObservableObject {
    private let server = CrazyEightsServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: CrazyEightsPhase = .lobby
    @Published var players: [CrazyEightsPlayer] = []
    @Published var canStart = false
    @Published var topCard: Card?
    @Published var activeSuit: Suit?
    @Published var currentName: String = ""
    @Published var hostIsCurrent = false
    @Published var hostHand: [Card] = []
    @Published var drawCount = 0
    @Published var justDrew = false
    @Published var lastEvent: String?
    @Published var winnerLabel = ""
    @Published var options = CrazyEightsOptions()
    @Published var customHandSize = false
    @Published var handSizeValue = 5
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do { joinUrl = try server.start() } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func applyOptions(_ o: CrazyEightsOptions) { server.hostSetOptions(o) }
    func start() { server.hostStart() }
    func play(_ c: Card, declaredSuit: Suit?) { _ = server.hostPlay(c, declaredSuit: declaredSuit) }
    func draw() { server.hostDraw() }
    func pass() { server.hostPass() }
    func newGame() { server.hostNewGame() }
    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }
    func stop() { server.stop(); joinUrl = nil }

    func canPlay(_ c: Card) -> Bool { server.engine.canPlay(c) }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = Array(e.players.values).sorted { $0.id < $1.id }
        canStart = e.canStart
        topCard = e.topCard
        activeSuit = e.activeSuit
        currentName = e.current?.name ?? ""
        hostIsCurrent = e.current?.id == CrazyEightsServer.hostId
        hostHand = e.players[CrazyEightsServer.hostId]?.hand ?? []
        drawCount = e.drawPile.count
        justDrew = e.justDrew
        lastEvent = e.lastEvent
        if let wid = e.winnerId, let w = e.players[wid] {
            winnerLabel = "\(w.name) wins"
        } else { winnerLabel = "" }
        if options != e.options { options = e.options }
        customHandSize = e.options.startingHandSize != nil
        if let s = e.options.startingHandSize, handSizeValue != s { handSizeValue = s }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
