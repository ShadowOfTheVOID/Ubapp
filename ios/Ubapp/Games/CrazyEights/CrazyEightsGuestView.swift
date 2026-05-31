import SwiftUI

/// Native guest UI for Crazy Eights — wire protocol from `crazy_eights_browser.html`.
struct CrazyEightsGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = CrazyEightsGuestModel()
    @State private var suitPickFor: CrazyEightsGuestModel.Card?
    @State private var showInterstitial = false
    @State private var interstitialFired = false

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("Crazy 8s")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .sheet(item: $suitPickFor) { card in suitPicker(card: card) }
        .ubappChrome()
    }

    @ViewBuilder private var lobby: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Crazy 8s · lobby", color: UbappTheme.accent)
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
                ForEach(model.players, id: \.id) { p in playerRow(p) }
            }
        }
    }

    private func playerRow(_ p: CrazyEightsGuestModel.Player) -> some View {
        HStack(spacing: 12) {
            Avatar(name: p.name, host: p.isHost, size: 32)
            Text(p.name).font(.system(size: 15, weight: p.id == ctx.yourId ? .bold : .semibold))
                .foregroundStyle(.white)
            if p.id == ctx.yourId { MonoLabel("you", size: 9, color: UbappTheme.accent) }
            Spacer()
            if p.isHost { MonoLabel("host", size: 9, color: UbappTheme.faint) }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .ubCard(radius: UbappRadius.row)
    }

    @ViewBuilder private var table: some View {
        turnHeader
        playersStrip
        tableArea
        if !model.lastEvent.isEmpty {
            MonoLabel(model.lastEvent, size: 10, color: UbappTheme.muted)
        }
        handArea
        actionBar
    }

    private var turnHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel("Crazy 8s", color: UbappTheme.accent)
            Text(isMyTurn ? "Your turn" : "\(currentName)'s turn")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8)
                .foregroundStyle(isMyTurn ? UbappTheme.accent : .white)
            Text("Match \(suitGlyph(model.activeSuit ?? model.topCard?.suit ?? "")) or rank — or play an 8.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
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

    private var tableArea: some View {
        HStack(spacing: 26) {
            VStack(spacing: 8) {
                ZStack {
                    GridCardBack(width: 70)
                    VStack(spacing: 0) {
                        Text("\(model.drawCount)").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        Text("draw").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                MonoLabel("Draw · \(model.drawCount)", size: 9)
            }
            VStack(spacing: 8) {
                if let top = model.topCard {
                    cardView(top, faceUp: true)
                } else {
                    Color.clear.frame(width: 70, height: 98)
                }
                MonoLabel("Suit \(suitGlyph(model.activeSuit ?? model.topCard?.suit ?? ""))",
                          size: 9, color: UbappTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RadialGradient(colors: [UbappTheme.accent.opacity(0.12), .clear],
                           center: .center, startRadius: 0, endRadius: 180),
        )
        .clipShape(RoundedRectangle(cornerRadius: UbappRadius.hero, style: .continuous))
    }

    private var handArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Your hand · \(model.hand.count)")
            let cols = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(model.hand.enumerated()), id: \.offset) { _, card in
                    Button {
                        guard isMyTurn, isPlayable(card) else { return }
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

    @ViewBuilder private var actionBar: some View {
        if isMyTurn {
            HStack(spacing: 10) {
                if model.justDrew {
                    Button("Pass") { model.send(["type": "pass"]) }
                        .buttonStyle(UbSecondaryButtonStyle())
                }
                Button(model.justDrew ? "Drew — pass or play" : "Draw") { model.send(["type": "draw"]) }
                    .buttonStyle(UbSecondaryButtonStyle())
                    .disabled(model.justDrew)
                    .opacity(model.justDrew ? 0.5 : 1)
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
            MonoLabel("Choose the next suit", color: UbappTheme.accent)
            let suits = ["clubs", "diamonds", "hearts", "spades"]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suits, id: \.self) { s in
                    Button {
                        model.send(["type": "play", "suit": card.suit, "rank": card.rank, "declaredSuit": s])
                        suitPickFor = nil
                    } label: {
                        Text(suitGlyph(s)).font(.system(size: 40))
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .foregroundStyle(s == "diamonds" || s == "hearts"
                                             ? UbappTheme.accent : .white)
                            .ubAccentCard(radius: UbappRadius.button)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Cancel") { suitPickFor = nil }
                .buttonStyle(UbSecondaryButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(UbappTheme.canvas)
        .presentationDetents([.medium])
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
