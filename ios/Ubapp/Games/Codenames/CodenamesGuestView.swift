import SwiftUI

/// Native guest UI for Codenames — wire protocol from `codenames_browser.html`.
struct CodenamesGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = CodenamesGuestModel()
    @State private var clueText: String = ""
    @State private var clueNumber: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
                switch model.phase {
                case "lobby":    lobby
                case "gameOver": board
                default:         board
                }
            }
            .padding()
        }
        .navigationTitle("Codenames")
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
    }

    @ViewBuilder private var lobby: some View {
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        GroupBox("Pick a team") {
            HStack {
                Button("Join Red") { model.send(["type": "team", "team": "red"]) }
                    .buttonStyle(.borderedProminent).tint(.red)
                Button("Join Blue") { model.send(["type": "team", "team": "blue"]) }
                    .buttonStyle(.borderedProminent).tint(.blue)
            }
            Button(model.isSpymaster ? "Step down as spymaster" : "Be Spymaster") {
                model.send(["type": "spymaster", "on": !model.isSpymaster])
            }
            .buttonStyle(.bordered).disabled(model.myTeam == nil)
        }
        GroupBox("Players") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name).fontWeight(p.id == ctx.yourId ? .bold : .regular)
                    if let t = p.team {
                        Text(t).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(t == "red" ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    if p.isSpymaster {
                        Text("spy").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        Text("Need ≥2 per team and a spymaster each. Host starts when ready.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var board: some View {
        scoreboard
        turnBanner
        clueArea
        boardGrid
        if model.phase != "gameOver",
           !model.isSpymaster, model.currentTeam == model.myTeam, model.currentClue != nil {
            Button("End turn") { model.send(["type": "end_turn"]) }.buttonStyle(.bordered)
        }
        if !model.lastEvent.isEmpty {
            Text(model.lastEvent).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder private var scoreboard: some View {
        HStack(spacing: 8) {
            VStack { Text("RED").font(.caption.bold()); Text("\(model.redLeft)").font(.title2.bold()) }
                .frame(maxWidth: .infinity).padding(8).background(Color.red).cornerRadius(8)
                .foregroundStyle(.white)
            VStack { Text("BLUE").font(.caption.bold()); Text("\(model.blueLeft)").font(.title2.bold()) }
                .frame(maxWidth: .infinity).padding(8).background(Color.blue).cornerRadius(8)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var turnBanner: some View {
        if model.phase == "gameOver" {
            let w = (model.winner ?? "").uppercased()
            Text("\(w) wins. \(model.endReason)").font(.headline)
                .frame(maxWidth: .infinity).padding()
                .background((model.winner == "red" ? Color.red : Color.blue).opacity(0.2))
                .cornerRadius(8)
        } else {
            let team = (model.currentTeam ?? "").uppercased()
            let mine = model.currentTeam == model.myTeam
            Text("\(team)'s turn\(mine ? " — you" : "")\(model.isSpymaster ? " (spymaster)" : "")")
                .font(.headline)
                .frame(maxWidth: .infinity).padding()
                .background((model.currentTeam == "red" ? Color.red : Color.blue).opacity(0.2))
                .cornerRadius(8)
        }
    }

    @ViewBuilder private var clueArea: some View {
        if let clue = model.currentClue, model.phase != "gameOver" {
            Text("Clue: \"\(clue)\" · \(model.currentNumber) · \(model.guessesLeft) guesses left")
                .padding().frame(maxWidth: .infinity).background(.thinMaterial).cornerRadius(8)
        } else if model.isSpymaster, model.currentTeam == model.myTeam, model.phase != "gameOver" {
            GroupBox("Your clue (one word + number)") {
                HStack {
                    TextField("WORD", text: $clueText).textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Stepper("\(clueNumber)", value: $clueNumber, in: 0...9)
                }
                Button("Submit clue") {
                    let c = clueText.trimmingCharacters(in: .whitespaces)
                    guard !c.isEmpty else { return }
                    model.send(["type": "clue", "clue": c, "number": clueNumber])
                    clueText = ""
                }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder private var boardGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(Array(model.board.enumerated()), id: \.offset) { i, card in
                tile(card: card, index: i)
            }
        }
    }

    @ViewBuilder
    private func tile(card: CodenamesGuestModel.Tile, index: Int) -> some View {
        let canGuess = !model.isSpymaster
            && model.currentTeam == model.myTeam
            && model.currentClue != nil
            && model.guessesLeft > 0
            && !card.revealed
            && model.phase != "gameOver"
        let smKind: String? = model.isSpymaster
            ? (index < model.smView.count ? model.smView[index] : nil)
            : nil
        let bg = tileBackground(card: card, smKind: smKind)
        let fg: Color = card.revealed && (card.kind == "red" || card.kind == "blue" || card.kind == "assassin")
            ? .white : .black
        Button {
            guard canGuess else { return }
            model.send(["type": "guess", "index": index])
        } label: {
            Text(card.word).font(.caption.bold())
                .multilineTextAlignment(.center)
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(bg)
                .foregroundStyle(fg)
                .opacity(card.revealed ? 0.5 : 1.0)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!canGuess)
    }

    private func tileBackground(card: CodenamesGuestModel.Tile, smKind: String?) -> Color {
        if card.revealed {
            return tileColor(card.kind)
        }
        if let k = smKind { return tileColor(k).opacity(0.35) }
        return Color(red: 0.85, green: 0.78, blue: 0.61)
    }
    private func tileColor(_ kind: String) -> Color {
        switch kind {
        case "red": .red; case "blue": .blue; case "neutral": Color(.systemGray); case "assassin": .black
        default: Color(.systemGray4)
        }
    }
}

@MainActor
final class CodenamesGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool
        let team: String?; let isSpymaster: Bool }
    struct Tile { let word: String; let kind: String; let revealed: Bool }

    @Published var players: [Player] = []
    @Published var phase: String = "lobby"
    @Published var board: [Tile] = []
    @Published var smView: [String] = []     // spymaster's per-tile kind hints
    @Published var isSpymaster = false
    @Published var myTeam: String?
    @Published var currentTeam: String?
    @Published var currentClue: String?
    @Published var currentNumber: Int = 0
    @Published var guessesLeft: Int = 0
    @Published var redLeft = 0
    @Published var blueLeft = 0
    @Published var winner: String?
    @Published var endReason: String = ""
    @Published var lastEvent: String = ""
    @Published var tutorialState = GuestTutorialState()
    @Published var tutorialContent: GuestTutorialContent?
    @Published var myTutorialVote: Bool?

    private weak var client: (any GuestLink)?

    func attach(ctx: GuestContext) {
        client = ctx.client
        ctx.client.onMessage = { [weak self] msg in self?.handle(msg) }
        for m in ctx.replay { handle(m) }
    }

    func send(_ payload: [String: Any]) { client?.send(payload) }

    private func handle(_ m: [String: Any]) {
        guard let type = m["type"] as? String else { return }
        switch type {
        case "lobby":
            let arr = m["players"] as? [[String: Any]] ?? []
            players = arr.map { Player(id: $0["id"] as? String ?? "",
                                       name: $0["name"] as? String ?? "",
                                       isHost: $0["isHost"] as? Bool ?? false,
                                       team: $0["team"] as? String,
                                       isSpymaster: $0["isSpymaster"] as? Bool ?? false) }
            phase = "lobby"
        case "role":
            isSpymaster = m["isSpymaster"] as? Bool ?? false
            myTeam = m["team"] as? String
            if let sm = m["smView"] as? [[String: Any]] {
                smView = sm.map { $0["kind"] as? String ?? "neutral" }
            } else { smView = [] }
        case "state":
            if let b = m["board"] as? [[String: Any]] {
                board = b.map { Tile(word: $0["word"] as? String ?? "",
                                     kind: $0["kind"] as? String ?? "",
                                     revealed: $0["revealed"] as? Bool ?? false) }
            }
            currentTeam = m["currentTeam"] as? String
            currentClue = m["currentClue"] as? String
            currentNumber = m["currentNumber"] as? Int ?? 0
            guessesLeft = m["guessesLeft"] as? Int ?? 0
            redLeft = m["redLeft"] as? Int ?? redLeft
            blueLeft = m["blueLeft"] as? Int ?? blueLeft
            phase = m["phase"] as? String ?? phase
            winner = m["winner"] as? String
            endReason = m["endReason"] as? String ?? ""
            lastEvent = m["lastEvent"] as? String ?? ""
        case "reset":
            phase = "lobby"; board = []; winner = nil; smView = []
        case "tutorial_vote_state":
            tutorialState.apply(m)
            if let title = m["title"] as? String {
                tutorialContent = GuestTutorialContent(title: title,
                    sections: GuestTutorialContent.readSections(m["sections"]),
                    menuSections: GuestTutorialContent.readSections(m["menuSections"]))
            }
        default: break
        }
    }
}
