import SwiftUI

/// Native guest UI for Cheat — wire protocol from `cheat_browser.html`.
struct CheatGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = CheatGuestModel()
    @State private var selected: Set<String> = []

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .center, spacing: 12) {
                        Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
                        switch model.phase {
                        case "lobby":    lobby
                        case "gameOver": gameOver
                        default:         table
                        }
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
            .navigationTitle("Cheat")
            .onAppear { model.attach(ctx: ctx) }
            .onDisappear { ctx.client.onMessage = nil }
        }
        .ubappChrome()
    }

    @ViewBuilder private var lobby: some View {
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        GroupBox("Players (\(model.players.count))") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name).fontWeight(p.id == ctx.yourId ? .bold : .regular)
                    if p.isHost { Text("host").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
            }
        }
        Text("Waiting for the host to deal…").foregroundStyle(.secondary).font(.caption)
    }

    @ViewBuilder private var table: some View {
        playersStrip
        pileCard
        if let reveal = model.lastReveal { revealCard(reveal) }
        if !model.lastEvent.isEmpty {
            Text(model.lastEvent).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        if model.phase == "pendingWin" { pendingWinControls }
        if isMyTurn && model.phase == "playing" { turnInstructions }
        hand
        actionRow
    }

    @ViewBuilder private var playersStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    VStack(spacing: 4) {
                        Text(p.name).font(.caption.bold())
                        Text("\(p.handCount) cards").font(.caption2)
                    }
                    .padding(8).frame(minWidth: 80)
                    .background(model.currentId == p.id ? Color.accentColor : Color.white.opacity(0.04))
                    .foregroundStyle(model.currentId == p.id ? .white : .primary)
                    .cornerRadius(8)
                }
            }
        }
    }

    @ViewBuilder private var pileCard: some View {
        GroupBox {
            VStack(spacing: 6) {
                ZStack {
                    if model.pileSize > 0 {
                        ForEach(0..<min(model.pileSize, 4), id: \.self) { i in
                            GridCardBack(width: 56)
                                .rotationEffect(.degrees(Double(i % 2 == 0 ? -1 : 1) * Double(i + 1)))
                                .offset(x: CGFloat(i) * 1.5, y: CGFloat(i) * 1.5)
                        }
                    } else {
                        Color.clear.frame(width: 56, height: 78)
                    }
                }
                .frame(height: 84)
                Text("Pile: \(model.pileSize) card\(model.pileSize == 1 ? "" : "s")")
                    .font(.subheadline)
                if let lp = model.lastPlay {
                    let accuser = model.players.first { $0.id == lp.playerId }?.name ?? "?"
                    Text("\(accuser) claimed \(lp.count) × \(rankName(lp.claimedRank))")
                        .font(.callout.bold())
                }
                Text("Next expected: \(rankName(model.expectedRank))")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func revealCard(_ r: CheatGuestModel.Reveal) -> some View {
        GroupBox(r.truthful ? "Truthful claim" : "Caught cheating!") {
            let accused = model.players.first { $0.id == r.accusedId }?.name ?? "?"
            let caller = model.players.first { $0.id == r.callerId }?.name ?? "?"
            let loser = model.players.first { $0.id == r.loserId }?.name ?? "?"
            Text("\(caller) called BS on \(accused) (\(rankName(r.claimedRank)))")
                .font(.caption)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(r.cards.enumerated()), id: \.offset) { _, c in
                        cardChip(c, faceUp: true)
                    }
                }
            }
            Text("\(loser) picks up the pile.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var pendingWinControls: some View {
        let w = model.players.first { $0.id == model.winnerId }
        GroupBox("Pending win") {
            Text("\(w?.name ?? "?") played their last card claiming \(rankName(model.lastPlay?.claimedRank ?? 0)).")
                .font(.caption)
            if ctx.yourId != model.winnerId {
                HStack {
                    Button(role: .destructive) { model.send(["type": "bs"]) } label: {
                        Text("Call BS").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.red)
                    Button { model.send(["type": "accept_win"]) } label: {
                        Text("Accept win").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.green)
                }
            } else {
                Text("Wait for the others to call BS or accept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var turnInstructions: some View {
        Text("Your turn — pick cards and play as \(rankName(model.expectedRank))")
            .font(.headline).foregroundStyle(.green)
    }

    @ViewBuilder private var hand: some View {
        GroupBox("Your hand (\(model.hand.count))") {
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
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selected.contains(key) ? Color.accentColor : Color.clear, lineWidth: 3)
                            )
                            .offset(y: selected.contains(key) ? -8 : 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var actionRow: some View {
        HStack {
            // BS button is visible whenever there's an open play we didn't make.
            if let lp = model.lastPlay, lp.playerId != ctx.yourId, model.phase == "playing" {
                Button(role: .destructive) { model.send(["type": "bs"]) } label: {
                    Text("Call BS").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.red)
            }
            if isMyTurn && model.phase == "playing" {
                Button {
                    let picked = pickedCards()
                    guard !picked.isEmpty else { return }
                    model.send(["type": "play",
                                "claimedRank": model.expectedRank,
                                "cards": picked.map { ["suit": $0.suit, "rank": $0.rank] }])
                    selected.removeAll()
                } label: {
                    Text("Play \(selected.count) × \(rankName(model.expectedRank))")
                        .frame(maxWidth: .infinity)
                }
                .disabled(selected.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder private var gameOver: some View {
        let winner = model.players.first { $0.id == model.winnerId }
        GroupBox("Game over") {
            Text("\(winner?.name ?? "?") wins!").font(.title2.bold())
            ForEach(model.players, id: \.id) { p in
                HStack { Text(p.name); Spacer(); Text("\(p.handCount) cards left")
                    .foregroundStyle(.secondary).font(.footnote) }
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
