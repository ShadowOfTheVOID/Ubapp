import SwiftUI

/// Native guest UI for Crazy Eights — wire protocol from `crazy_eights_browser.html`.
struct CrazyEightsGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = CrazyEightsGuestModel()
    @State private var suitPickFor: CrazyEightsGuestModel.Card?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .center, spacing: 12) {
                        Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
                        SeriesBanner(state: model.series)
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
            .navigationTitle("Crazy Eights")
            .onAppear { model.attach(ctx: ctx) }
            .onDisappear { ctx.client.onMessage = nil }
            .sheet(item: $suitPickFor) { card in suitPicker(card: card) }
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
        topCard
        if !model.lastEvent.isEmpty {
            Text(model.lastEvent).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        hand
        if isMyTurn {
            HStack {
                if model.justDrew {
                    Button("Pass") { model.send(["type": "pass"]) }.buttonStyle(.bordered)
                }
                Button("Draw") { model.send(["type": "draw"]) }
                    .disabled(model.justDrew)
                    .buttonStyle(.bordered)
            }
        }
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

    @ViewBuilder private var topCard: some View {
        GroupBox {
            VStack {
                HStack(spacing: 24) {
                    ZStack {
                        GridCardBack(width: 64)
                        VStack(spacing: 0) {
                            Text("\(model.drawCount)")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            Text("draw")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }

                    if let top = model.topCard {
                        cardView(top, faceUp: true)
                    } else {
                        Color.clear.frame(width: 64, height: 90)
                    }
                }
                Text("Active suit: \(suitGlyph(model.activeSuit ?? model.topCard?.suit ?? ""))")
                    .font(.subheadline)
                Text(isMyTurn ? "Your turn" : "\(currentName)'s turn")
                    .font(.headline).foregroundStyle(isMyTurn ? .green : .secondary)
            }.padding(.vertical, 4)
        }
    }

    @ViewBuilder private var hand: some View {
        GroupBox("Your hand (\(model.hand.count))") {
            let cols = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(model.hand.enumerated()), id: \.offset) { _, card in
                    Button {
                        guard isMyTurn else { return }
                        guard isPlayable(card) else { return }
                        if card.rank == 8 { suitPickFor = card }
                        else { model.send(["type": "play", "suit": card.suit, "rank": card.rank]) }
                    } label: {
                        cardView(card, faceUp: true)
                            .opacity(isPlayable(card) && isMyTurn ? 1.0 : 0.4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func cardView(_ c: CrazyEightsGuestModel.Card, faceUp: Bool) -> some View {
        if let suit = CardSuit.fromWire(c.suit), faceUp {
            NoirCardFace(rank: c.rank, suit: suit, width: 64, wildAccent: true)
        } else {
            GridCardBack(width: 64)
        }
    }

    @ViewBuilder
    private func suitPicker(card: CrazyEightsGuestModel.Card) -> some View {
        VStack(spacing: 16) {
            Text("Declare a new suit").font(.title3.bold())
            let suits = ["clubs", "diamonds", "hearts", "spades"]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(suits, id: \.self) { s in
                    Button {
                        model.send(["type": "play", "suit": card.suit, "rank": card.rank, "declaredSuit": s])
                        suitPickFor = nil
                    } label: {
                        Text(suitGlyph(s)).font(.system(size: 40))
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .background(Color.white.opacity(0.04))
                            .foregroundStyle(s == "diamonds" || s == "hearts" ? .red : .primary)
                            .cornerRadius(10)
                    }
                }
            }
            Button("Cancel") { suitPickFor = nil }
        }
        .padding()
        .presentationDetents([.medium])
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

    private var isMyTurn: Bool { model.currentId == ctx.yourId }
    private var currentName: String {
        model.players.first { $0.id == model.currentId }?.name ?? ""
    }

    private func isPlayable(_ c: CrazyEightsGuestModel.Card) -> Bool {
        guard let top = model.topCard else { return true }
        if c.rank == 8 { return true }
        let active = model.activeSuit ?? top.suit
        return c.suit == active || c.rank == top.rank
    }
}

private func suitGlyph(_ s: String) -> String {
    switch s { case "clubs": "♣"; case "diamonds": "♦"; case "hearts": "♥"; case "spades": "♠"; default: "" }
}
private func rankShort(_ r: Int) -> String {
    switch r { case 11: "J"; case 12: "Q"; case 13: "K"; case 14: "A"; default: "\(r)" }
}

@MainActor
final class CrazyEightsGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool; let handCount: Int }
    struct Card: Identifiable { var id: String { "\(suit)-\(rank)" }; let suit: String; let rank: Int }

    @Published var players: [Player] = []
    @Published var phase: String = "lobby"
    @Published var hand: [Card] = []
    @Published var topCard: Card?
    @Published var activeSuit: String?
    @Published var drawCount: Int = 0
    @Published var currentId: String?
    @Published var justDrew = false
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
            if let top = m["topCard"] as? [String: Any] {
                topCard = Card(suit: top["suit"] as? String ?? "",
                               rank: top["rank"] as? Int ?? 0)
            }
            activeSuit = m["activeSuit"] as? String
            drawCount = m["drawCount"] as? Int ?? drawCount
            currentId = m["currentId"] as? String
            justDrew = m["justDrew"] as? Bool ?? false
            lastEvent = m["lastEvent"] as? String ?? ""
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
            phase = "lobby"; hand = []; winnerId = nil
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
