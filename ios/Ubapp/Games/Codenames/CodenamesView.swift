import SwiftUI

/// Host's player UI for Codenames. Lobby has team / spymaster pickers; play
/// phase has the 5×5 board, clue input (spymaster), end-turn (operatives).
struct CodenamesView: View {
    @StateObject private var model = CodenamesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting)

                Text(phaseLabel).font(.headline)

                switch model.phase {
                case .lobby:
                    TutorialVoteCard(
                        state: model.tutorialState, tutorial: GameTutorials.codenames,
                        onCall: model.callTutorialVote, onVote: model.tutorialVote,
                        onDismiss: model.dismissTutorial)
                    lobbyView
                case .playing: playingView
                case .gameOver: gameOverView
                }
            }
            .padding()
        }
        .navigationTitle("Codenames")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var lobbyView: some View {
        GroupBox("Your team") {
            HStack {
                Button("Join Red") { model.joinTeam(.red) }
                    .buttonStyle(.borderedProminent).tint(.red)
                Button("Join Blue") { model.joinTeam(.blue) }
                    .buttonStyle(.borderedProminent).tint(.blue)
            }
            Toggle("I'm spymaster", isOn: $model.hostIsSpymaster)
                .onChange(of: model.hostIsSpymaster) { _, on in model.setSpymaster(on) }
        }
        GroupBox("Players") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text(p.team?.name2.capitalized ?? "—")
                        .foregroundStyle(p.team == .red ? .red : p.team == .blue ? .blue : .secondary)
                    if p.isSpymaster { Text("(SM)").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        GroupBox("Options") {
            Picker("Board size", selection: $model.boardSize) {
                ForEach(CodenamesOptions.allowedSizes, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }.pickerStyle(.segmented)
            .onChange(of: model.boardSize) { _, v in
                model.applyOptions(CodenamesOptions(boardSize: v, assassinCount: model.assassinCount))
            }
            Stepper(value: $model.assassinCount, in: 1...3) {
                Text("Assassins: \(model.assassinCount)")
            }
            .onChange(of: model.assassinCount) { _, v in
                model.applyOptions(CodenamesOptions(boardSize: model.boardSize, assassinCount: v))
            }
        }
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need ≥2 per team with a spymaster on each side.")
                .foregroundStyle(.secondary).font(.callout)
        }
    }

    @ViewBuilder private var playingView: some View {
        GroupBox {
            HStack {
                Text("Turn: \(model.currentTeam.name2.capitalized)")
                    .foregroundStyle(model.currentTeam == .red ? .red : .blue).bold()
                Spacer()
                Text("Red \(model.redLeft) · Blue \(model.blueLeft)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        if let clue = model.currentClue {
            GroupBox("Clue") {
                Text("\(clue.uppercased()) · \(model.currentNumber)")
                    .font(.title3.bold())
                if model.guessesLeftThisTurn > 0 {
                    Text("\(model.guessesLeftThisTurn) guesses left").font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if model.hostIsCurrentSpymaster {
            GroupBox("Give a clue") {
                TextField("Word", text: $model.clueDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper("Number: \(model.clueNumber)", value: $model.clueNumber, in: 0...9)
                Button("Send clue") { model.sendClue() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.clueDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }

        boardGrid

        if !model.hostIsCurrentSpymaster, model.currentClue != nil,
           model.guessesLeftThisTurn != model.currentNumber + 1 {
            Button("End turn") { model.endTurn() }
        }
    }

    @ViewBuilder private var boardGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(model.cards.indices, id: \.self) { i in
                let c = model.cards[i]
                Button {
                    model.guess(i)
                } label: {
                    Text(c.word)
                        .font(.caption).bold()
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(4)
                        .background(color(for: c))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(c.revealed || model.hostIsCurrentSpymaster
                          || model.currentClue == nil || model.guessesLeftThisTurn <= 0)
            }
        }
    }

    private func color(for c: CodenamesViewModel.CardSnap) -> Color {
        if c.revealed {
            switch c.kind {
            case "red": return .red
            case "blue": return .blue
            case "assassin": return .black
            default: return .gray
            }
        }
        // Spymaster sees the underlying allegiance even when unrevealed.
        if model.hostIsAnySpymaster, let k = c.smKind {
            switch k {
            case "red": return .red.opacity(0.4)
            case "blue": return .blue.opacity(0.4)
            case "assassin": return .black.opacity(0.5)
            default: return .gray.opacity(0.3)
            }
        }
        return .gray.opacity(0.3)
    }

    @ViewBuilder private var gameOverView: some View {
        GroupBox("Result") {
            Text(model.winnerLabel).font(.title2.bold())
            if let r = model.endReason { Text(r).foregroundStyle(.secondary) }
        }
        Button("New game") { model.newGame() }.buttonStyle(.borderedProminent)
    }

    private var phaseLabel: String {
        switch model.phase {
        case .lobby: "Lobby"; case .playing: "Playing"; case .gameOver: "Game over"
        }
    }
}

@MainActor
final class CodenamesViewModel: ObservableObject {
    struct CardSnap {
        let word: String
        let revealed: Bool
        /// Kind once revealed ("red"/"blue"/"neutral"/"assassin"), nil if hidden.
        let kind: String
        /// Underlying allegiance for the spymaster view.
        let smKind: String?
    }

    private let server = CodenamesServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: CodenamesPhase = .lobby
    @Published var players: [CodenamesPlayer] = []
    @Published var canStart = false
    @Published var cards: [CardSnap] = []
    @Published var currentTeam: Team = .red
    @Published var currentClue: String?
    @Published var currentNumber = 0
    @Published var guessesLeftThisTurn = 0
    @Published var redLeft = 0
    @Published var blueLeft = 0
    @Published var hostIsSpymaster = false
    @Published var clueDraft = ""
    @Published var clueNumber = 1
    @Published var winnerLabel = ""
    @Published var endReason: String?
    @Published var boardSize: Int = 25
    @Published var assassinCount: Int = 1
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    var hostIsAnySpymaster: Bool {
        server.engine.players[CodenamesServer.hostId]?.isSpymaster == true
    }
    var hostIsCurrentSpymaster: Bool {
        guard let p = server.engine.players[CodenamesServer.hostId] else { return false }
        return p.isSpymaster && p.team == currentTeam
    }

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do { joinUrl = try server.start() } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func joinTeam(_ t: Team) { server.hostJoinTeam(t) }
    func setSpymaster(_ on: Bool) { server.hostSetSpymaster(on) }
    func applyOptions(_ o: CodenamesOptions) { server.hostSetOptions(o) }
    func start() { server.hostStart() }
    func sendClue() {
        let c = clueDraft.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty {
            server.hostSubmitClue(c, number: clueNumber)
            clueDraft = ""
        }
    }
    func guess(_ index: Int) { server.hostGuess(index) }
    func endTurn() { server.hostEndTurn() }
    func newGame() { server.hostNewGame() }
    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }
    func stop() { server.stop() }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = Array(e.players.values).sorted { $0.id < $1.id }
        canStart = e.canStart
        currentTeam = e.currentTeam
        currentClue = e.currentClue
        currentNumber = e.currentNumber
        guessesLeftThisTurn = e.guessesLeftThisTurn
        redLeft = e.cardsLeftFor(team: .red)
        blueLeft = e.cardsLeftFor(team: .blue)
        cards = e.board.map { c in
            CardSnap(word: c.word, revealed: c.revealed,
                     kind: c.kind.rawValue,
                     smKind: hostIsAnySpymaster ? c.kind.rawValue : nil)
        }
        hostIsSpymaster = e.players[CodenamesServer.hostId]?.isSpymaster ?? false
        if let w = e.winner {
            winnerLabel = "\(w.name2.uppercased()) wins"
        } else { winnerLabel = "" }
        endReason = e.endReason
        if boardSize != e.options.boardSize { boardSize = e.options.boardSize }
        if assassinCount != e.options.assassinCount { assassinCount = e.options.assassinCount }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
