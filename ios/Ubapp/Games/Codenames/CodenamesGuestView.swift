import SwiftUI

/// Native guest UI for Codenames — wire protocol from `codenames_browser.html`.
struct CodenamesGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = CodenamesGuestModel()
    @State private var clueText: String = ""
    @State private var clueNumber: Int = 1
    @State private var showInterstitial = false
    @State private var interstitialFired = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SeriesBanner(state: model.series)
                    if model.phase == "lobby" { lobby } else { board }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .scrollIndicators(.hidden)
            if model.phase == "gameOver" {
                AdBannerView()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .adInterstitial(isPresented: $showInterstitial)
        .onChange(of: model.phase) { _, newPhase in
            if newPhase == "gameOver" && !interstitialFired {
                interstitialFired = true
                showInterstitial = true
            }
        }
        .navigationTitle("Codenames")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .ubappChrome()
    }

    @ViewBuilder private var lobby: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Codenames · lobby", color: UbappTheme.accent)
            Text("Pick your team")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
            Text("Playing as \(ctx.yourName)")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        HStack(spacing: 10) {
            teamPickButton("Join Red", team: "red", color: CN.red)
            teamPickButton("Join Blue", team: "blue", color: CN.blue)
        }
        Button(model.isSpymaster ? "Step down as spymaster" : "Become spymaster ★") {
            model.send(["type": "spymaster", "on": !model.isSpymaster])
        }
        .buttonStyle(UbSecondaryButtonStyle())
        .disabled(model.myTeam == nil).opacity(model.myTeam == nil ? 0.5 : 1)

        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("In the room · \(model.players.count)")
            VStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: p.id == ctx.yourId ? .bold : .semibold))
                            .foregroundStyle(.white)
                        if p.isSpymaster { MonoLabel("spy ★", size: 9, color: CN.color(p.team ?? "")) }
                        Spacer()
                        if let t = p.team {
                            MonoLabel(t, size: 9, color: t == "red" ? CN.red : CN.blue)
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row)
                }
            }
        }
        Text("Need ≥2 per team and a spymaster each. Host starts when ready.")
            .font(.system(size: 12)).foregroundStyle(UbappTheme.muted)
    }

    private func teamPickButton(_ title: String, team: String, color: Color) -> some View {
        Button { model.send(["type": "team", "team": team]) } label: {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(model.myTeam == team ? .white : color)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(model.myTeam == team ? color : color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: UbappRadius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: UbappRadius.button, style: .continuous)
                    .stroke(color.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var board: some View {
        header
        scoreboard
        clueArea
        boardGrid
        if model.phase != "gameOver",
           !model.isSpymaster, model.currentTeam == model.myTeam, model.currentClue != nil {
            Button("End turn") { model.send(["type": "end_turn"]) }
                .buttonStyle(UbSecondaryButtonStyle())
        }
        if !model.lastEvent.isEmpty { MonoLabel(model.lastEvent, size: 10, color: UbappTheme.muted) }
    }

    @ViewBuilder private var header: some View {
        if model.phase == "gameOver" {
            let w = model.winner ?? ""
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Game over · assassin or sweep", color: CN.color(w))
                Text("\(w.capitalized) wins")
                    .font(.system(size: 28, weight: .heavy)).kerning(-0.8)
                    .foregroundStyle(CN.color(w))
                if !model.endReason.isEmpty {
                    Text(model.endReason).font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
                }
            }
        } else {
            let team = model.currentTeam ?? ""
            let mine = model.currentTeam == model.myTeam
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("Codenames", color: UbappTheme.accent)
                Text(mine ? (model.isSpymaster ? "Your clue" : "Your team guesses")
                          : "\(team.capitalized)'s turn")
                    .font(.system(size: 24, weight: .heavy)).kerning(-0.7)
                    .foregroundStyle(mine ? CN.color(team) : .white)
            }
        }
    }

    private var scoreboard: some View {
        HStack(spacing: 10) {
            teamScore("Red", left: model.redLeft, color: CN.red)
            teamScore("Blue", left: model.blueLeft, color: CN.blue)
        }
    }

    private func teamScore(_ name: String, left: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel("\(name) · left", size: 10, color: color)
            Text("\(left)").font(.system(size: 28, weight: .heavy)).kerning(-0.6).foregroundStyle(color)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: UbappRadius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: UbappRadius.row, style: .continuous)
            .stroke(color.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder private var clueArea: some View {
        if let clue = model.currentClue, model.phase != "gameOver" {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel("Clue", size: 9, color: CN.color(model.currentTeam ?? ""))
                    Text("“\(clue)”")
                        .font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(.white)
                }
                Spacer()
                Text("\(model.currentNumber)")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(CN.color(model.currentTeam ?? ""))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                MonoLabel("\(model.guessesLeft) left", size: 9, color: UbappTheme.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .ubCard(radius: UbappRadius.panel)
        } else if model.isSpymaster, model.currentTeam == model.myTeam, model.phase != "gameOver" {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("Compose clue · one word + a number")
                HStack(spacing: 10) {
                    TextField("", text: $clueText,
                              prompt: Text("WORD").foregroundColor(UbappTheme.faint))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .padding(12).ubCard(radius: UbappRadius.button)
                    Stepper("\(clueNumber)", value: $clueNumber, in: 0...9)
                        .fixedSize().tint(UbappTheme.accent)
                }
                Button("Give clue →") {
                    let c = clueText.trimmingCharacters(in: .whitespaces)
                    guard !c.isEmpty else { return }
                    model.send(["type": "clue", "clue": c, "number": clueNumber])
                    clueText = ""
                }
                .buttonStyle(UbPrimaryButtonStyle())
                .disabled(clueText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var boardGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 5)
        return LazyVGrid(columns: cols, spacing: 5) {
            ForEach(Array(model.board.enumerated()), id: \.offset) { i, card in
                tile(card: card, index: i)
            }
        }
        .padding(8)
        .background(Color(hex: 0x1A1A1A))
        .clipShape(RoundedRectangle(cornerRadius: UbappRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: UbappRadius.card, style: .continuous)
            .stroke(UbappTheme.line, lineWidth: 1))
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
        // Resolve appearance: revealed/gameOver show true color; spymaster sees key; else paper.
        let showColor = card.revealed || model.phase == "gameOver" || smKind != nil
        let kind = card.revealed || model.phase == "gameOver" ? card.kind : (smKind ?? "")
        let bg = showColor && !kind.isEmpty ? CN.color(kind) : CN.paper
        let fg = showColor && !kind.isEmpty ? CN.ink(kind) : CN.paperInk
        Button {
            guard canGuess else { return }
            model.send(["type": "guess", "index": index])
        } label: {
            Text(card.word)
                .font(.system(size: 11, weight: .bold, design: .serif))
                .kerning(0.4)
                .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.7)
                .padding(3)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(bg).foregroundStyle(fg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.25), lineWidth: 1),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(canGuess ? CN.color(model.myTeam ?? "") : Color.clear, lineWidth: 2),
                )
                .opacity(card.revealed ? 0.72 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!canGuess)
    }
}

private enum CN {
    static let red = Color(hex: 0xFF5A4A)
    static let redInk = Color(hex: 0x3A0A04)
    static let blue = Color(hex: 0x4F9EFF)
    static let blueInk = Color(hex: 0x02152E)
    static let bystander = Color(hex: 0xD8C590)
    static let bystanderInk = Color(hex: 0x2A2410)
    static let assassin = Color(hex: 0x0E0E10)
    static let assassinInk = Color.white
    static let paper = Color(hex: 0xF3ECD6)
    static let paperInk = Color(hex: 0x1C1C1F)

    static func color(_ kind: String) -> Color {
        switch kind {
        case "red": red; case "blue": blue; case "assassin": assassin
        case "neutral", "bystander": bystander; default: bystander
        }
    }
    static func ink(_ kind: String) -> Color {
        switch kind {
        case "red": redInk; case "blue": blueInk; case "assassin": assassinInk
        default: bystanderInk
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
    @Published var series = GuestSeriesState()

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
        case "series_state":
            series.apply(m)
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
