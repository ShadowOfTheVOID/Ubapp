import SwiftUI

/// Native guest UI for Cheat — wire protocol from `cheat_browser.html`.
struct CheatGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = CheatGuestModel()
    @State private var selected: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SeriesBanner(state: model.series)
                switch model.phase {
                case "lobby":    lobby
                case "gameOver": gameOver
                default:         table
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Cheat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .ubappChrome()
    }

    @ViewBuilder private var lobby: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Cheat · lobby", color: UbappTheme.accent)
            Text("Waiting for the deal")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
            Text("Playing as \(ctx.yourName)")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("In the room · \(model.players.count)")
            VStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: p.id == ctx.yourId ? .bold : .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        if p.isHost { MonoLabel("host", size: 9, color: UbappTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row)
                }
            }
        }
    }

    @ViewBuilder private var table: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel("Cheat", color: UbappTheme.accent)
            Text(isMyTurn && model.phase == "playing" ? "Your turn" : "\(currentName)'s turn")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8)
                .foregroundStyle(isMyTurn && model.phase == "playing" ? UbappTheme.accent : .white)
            Text("Claim \(rankName(model.expectedRank)) face-down — lie if you must.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
        playersStrip
        pileCard
        if let reveal = model.lastReveal { revealCard(reveal) }
        if !model.lastEvent.isEmpty { MonoLabel(model.lastEvent, size: 10, color: UbappTheme.muted) }
        if model.phase == "pendingWin" { pendingWinControls }
        hand
        actionRow
    }

    private var playersStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    let current = model.currentId == p.id
                    HStack(spacing: 8) {
                        Avatar(name: p.name, host: p.isHost, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            MonoLabel("\(p.handCount) cards", size: 9, color: UbappTheme.faint)
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .ubCard(radius: UbappRadius.button,
                            fill: current ? UbappTheme.accentSoft : UbappTheme.surface,
                            stroke: current ? UbappTheme.accentLine : UbappTheme.line)
                }
            }
        }
    }

    private var pileCard: some View {
        VStack(spacing: 10) {
            ZStack {
                if model.pileSize > 0 {
                    ForEach(0..<min(model.pileSize, 4), id: \.self) { i in
                        GridCardBack(width: 60)
                            .rotationEffect(.degrees(Double(i % 2 == 0 ? -1 : 1) * Double(i + 1)))
                            .offset(x: CGFloat(i) * 1.5, y: CGFloat(i) * 1.5)
                    }
                } else {
                    Color.clear.frame(width: 60, height: 84)
                }
            }
            .frame(height: 90)
            MonoLabel("Pile · \(model.pileSize)", size: 10)
            if let lp = model.lastPlay {
                let accuser = model.players.first { $0.id == lp.playerId }?.name ?? "?"
                Text("\(accuser) claimed \(lp.count) × \(rankName(lp.claimedRank))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(UbappTheme.onAccent)
                    .padding(.vertical, 5).padding(.horizontal, 12)
                    .background(UbappTheme.accent).clipShape(Capsule())
            }
            MonoLabel("Next expected · \(rankName(model.expectedRank))", size: 9, color: UbappTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RadialGradient(colors: [UbappTheme.accent.opacity(0.12), .clear],
                           center: .center, startRadius: 0, endRadius: 180),
        )
        .clipShape(RoundedRectangle(cornerRadius: UbappRadius.hero, style: .continuous))
    }

    @ViewBuilder
    private func revealCard(_ r: CheatGuestModel.Reveal) -> some View {
        let accused = model.players.first { $0.id == r.accusedId }?.name ?? "?"
        let caller = model.players.first { $0.id == r.callerId }?.name ?? "?"
        let loser = model.players.first { $0.id == r.loserId }?.name ?? "?"
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(r.truthful ? "Truthful claim" : "Caught cheating!",
                      color: r.truthful ? UbappTheme.online : UbappTheme.accent)
            Text("\(caller) called bluff on \(accused) · \(rankName(r.claimedRank))")
                .font(.system(size: 13)).foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(r.cards.enumerated()), id: \.offset) { _, c in
                        cardChip(c, faceUp: true)
                    }
                }
            }
            Text("\(loser) picks up the pile.")
                .font(.system(size: 12)).foregroundStyle(UbappTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(radius: UbappRadius.panel,
                fill: r.truthful ? UbappTheme.surface : UbappTheme.accentSoft,
                stroke: r.truthful ? UbappTheme.line : UbappTheme.accentLine)
    }

    @ViewBuilder private var pendingWinControls: some View {
        let w = model.players.first { $0.id == model.winnerId }
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Pending win", color: UbappTheme.accent)
            Text("\(w?.name ?? "?") played their last card claiming \(rankName(model.lastPlay?.claimedRank ?? 0)).")
                .font(.system(size: 13)).foregroundStyle(.white)
            if ctx.yourId != model.winnerId {
                HStack(spacing: 10) {
                    Button("Call bluff") { model.send(["type": "bs"]) }
                        .buttonStyle(UbSecondaryButtonStyle())
                    Button("Accept win") { model.send(["type": "accept_win"]) }
                        .buttonStyle(UbPrimaryButtonStyle())
                }
            } else {
                Text("Wait for the others to call bluff or accept.")
                    .font(.system(size: 12)).foregroundStyle(UbappTheme.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(radius: UbappRadius.panel)
    }

    private var hand: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Your hand · \(model.hand.count)")
            let cols = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(model.hand.enumerated()), id: \.offset) { _, card in
                    let key = "\(card.suit)-\(card.rank)-\(card.id)"
                    Button {
                        guard isMyTurn, model.phase == "playing" else { return }
                        if selected.contains(key) { selected.remove(key) }
                        else { selected.insert(key) }
                    } label: {
                        cardChip(card, faceUp: true)
                            .opacity(isMyTurn && model.phase == "playing" ? 1 : 0.6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selected.contains(key) ? UbappTheme.accent : Color.clear, lineWidth: 3),
                            )
                            .offset(y: selected.contains(key) ? -8 : 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var actionRow: some View {
        HStack(spacing: 10) {
            if let lp = model.lastPlay, lp.playerId != ctx.yourId, model.phase == "playing" {
                Button("Call cheat ✋") { model.send(["type": "bs"]) }
                    .buttonStyle(UbSecondaryButtonStyle())
            }
            if isMyTurn && model.phase == "playing" {
                Button("Play \(selected.count) × \(rankName(model.expectedRank))") {
                    let picked = pickedCards()
                    guard !picked.isEmpty else { return }
                    model.send(["type": "play",
                                "claimedRank": model.expectedRank,
                                "cards": picked.map { ["suit": $0.suit, "rank": $0.rank] }])
                    selected.removeAll()
                }
                .buttonStyle(UbPrimaryButtonStyle())
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.5 : 1)
            }
        }
    }

    private var currentName: String {
        model.players.first { $0.id == model.currentId }?.name ?? ""
    }

    @ViewBuilder private var gameOver: some View {
        let winner = model.players.first { $0.id == model.winnerId }
        let standings = model.players.sorted { $0.handCount < $1.handCount }
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Game over", color: UbappTheme.accent)
            Text("\(winner?.name ?? "?") wins")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
        }
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Final standings")
            VStack(spacing: 8) {
                ForEach(standings, id: \.id) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        if p.id == model.winnerId { Text("🏆") }
                        Spacer()
                        MonoLabel("\(p.handCount) left", size: 10, color: UbappTheme.muted)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row)
                }
            }
        }
    }

    @ViewBuilder
    private func cardChip(_ c: CheatGuestModel.Card, faceUp: Bool) -> some View {
        if let suit = CardSuit.fromWire(c.suit), faceUp {
            NoirCardFace(rank: c.rank, suit: suit, width: 64)
        } else {
            GridCardBack(width: 64)
        }
    }

    private var isMyTurn: Bool { model.currentId == ctx.yourId }

    private func pickedCards() -> [CheatGuestModel.Card] {
        model.hand.filter { selected.contains("\($0.suit)-\($0.rank)-\($0.id)") }
    }
}

@MainActor
final class CheatGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool; let handCount: Int }
    struct Card: Identifiable, Hashable { var id: String { "\(suit)-\(rank)" }; let suit: String; let rank: Int }
    struct LastPlay { let playerId: String; let claimedRank: Int; let count: Int }
    struct Reveal { let callerId: String; let accusedId: String; let claimedRank: Int
                    let cards: [Card]; let truthful: Bool; let loserId: String }

    @Published var players: [Player] = []
    @Published var phase: String = "lobby"
    @Published var hand: [Card] = []
    @Published var pileSize: Int = 0
    @Published var expectedRank: Int = 1
    @Published var lastPlay: LastPlay?
    @Published var lastReveal: Reveal?
    @Published var currentId: String?
    @Published var winnerId: String?
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
                                       handCount: $0["handCount"] as? Int ?? 0) }
            phase = "lobby"
        case "state":
            if let p = m["phase"] as? String { phase = p }
            if let arr = m["players"] as? [[String: Any]] {
                players = arr.map { Player(id: $0["id"] as? String ?? "",
                                           name: $0["name"] as? String ?? "",
                                           isHost: $0["isHost"] as? Bool ?? false,
                                           handCount: $0["handCount"] as? Int ?? 0) }
            }
            pileSize = m["pileSize"] as? Int ?? pileSize
            expectedRank = m["expectedRank"] as? Int ?? expectedRank
            currentId = m["currentId"] as? String
            winnerId = m["winnerId"] as? String
            lastEvent = m["lastEvent"] as? String ?? ""
            if let lp = m["lastPlay"] as? [String: Any] {
                lastPlay = LastPlay(playerId: lp["playerId"] as? String ?? "",
                                    claimedRank: lp["claimedRank"] as? Int ?? 0,
                                    count: lp["count"] as? Int ?? 0)
            } else { lastPlay = nil }
            if let r = m["lastReveal"] as? [String: Any] {
                let cs = (r["cards"] as? [[String: Any]]) ?? []
                lastReveal = Reveal(
                    callerId: r["callerId"] as? String ?? "",
                    accusedId: r["accusedId"] as? String ?? "",
                    claimedRank: r["claimedRank"] as? Int ?? 0,
                    cards: cs.map { Card(suit: $0["suit"] as? String ?? "", rank: $0["rank"] as? Int ?? 0) },
                    truthful: r["truthful"] as? Bool ?? false,
                    loserId: r["loserId"] as? String ?? "")
            } else { lastReveal = nil }
        case "hand":
            let cs = m["cards"] as? [[String: Any]] ?? []
            hand = cs.map { Card(suit: $0["suit"] as? String ?? "",
                                  rank: $0["rank"] as? Int ?? 0) }
        case "over":
            phase = "gameOver"
            winnerId = m["winnerId"] as? String
            if let arr = m["players"] as? [[String: Any]] {
                players = arr.map { Player(id: $0["id"] as? String ?? "",
                                           name: $0["name"] as? String ?? "",
                                           isHost: $0["isHost"] as? Bool ?? false,
                                           handCount: $0["handCount"] as? Int ?? 0) }
            }
        case "reset":
            phase = "lobby"; hand = []; winnerId = nil; lastPlay = nil; lastReveal = nil
            pileSize = 0; lastEvent = ""
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

fileprivate func suitGlyph(_ s: String) -> String {
    switch s { case "clubs": "♣"; case "diamonds": "♦"; case "hearts": "♥"; case "spades": "♠"; default: "" }
}
fileprivate func rankName(_ r: Int) -> String {
    switch r {
    case 1: "Aces"
    case 11: "Jacks"
    case 12: "Queens"
    case 13: "Kings"
    default: "\(r)s"
    }
}
