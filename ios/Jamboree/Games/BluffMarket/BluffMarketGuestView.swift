import SwiftUI

/// Native guest UI for Bluff Market — wire protocol from `bluff_market_browser.html`.
struct BluffMarketGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = BluffMarketGuestModel()
    @State private var selectedCardId: String?
    @State private var tradeTargetId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SeriesBanner(state: model.series)
                switch model.phase {
                case "lobby":    lobby
                case "scoring":  scoringView
                case "gameOver": overView
                default:         table
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Bluff Market")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .jamboreeChrome()
    }

    @ViewBuilder private var lobby: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Bluff Market · lobby", color: JamboreeTheme.accent)
            Text("Waiting for the deal")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
            Text("Playing as \(ctx.yourName)")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
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
                        if p.isHost { MonoLabel("host", size: 9, color: JamboreeTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: JamboreeRadius.row)
                }
            }
        }
    }

    @ViewBuilder private var table: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel("Bluff Market", color: JamboreeTheme.accent)
            Text(isMyTurn && model.phase == "playing" ? "Your turn" : "\(currentName)'s turn")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8)
                .foregroundStyle(isMyTurn && model.phase == "playing" ? JamboreeTheme.accent : .white)
            Text("Trade face-down, buy, or sell. One bomb is worth −25.")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
        }
        playersStrip
        marketCard
        if !model.lastEvent.isEmpty { MonoLabel(model.lastEvent, size: 10, color: JamboreeTheme.muted) }
        if let t = model.trade { tradeView(t) }
        hand
        if model.trade == nil && isMyTurn && model.phase == "playing" { actionRow }
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
                            MonoLabel("\(p.handCount)c·\(p.coins)¢", size: 9, color: JamboreeTheme.faint)
                            if !p.guaranteeUsed { MonoLabel("guar", size: 8, color: JamboreeTheme.accent) }
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .ubCard(radius: JamboreeRadius.button,
                            fill: current ? JamboreeTheme.accentSoft : JamboreeTheme.surface,
                            stroke: current ? JamboreeTheme.accentLine : JamboreeTheme.line)
                }
            }
        }
    }

    private var marketCard: some View {
        VStack(spacing: 10) {
            ZStack {
                if model.marketSize > 0 {
                    ForEach(0..<min(model.marketSize, 4), id: \.self) { i in
                        GridCardBack(width: 70)
                            .offset(x: CGFloat(i) * 1.5, y: CGFloat(i) * 1.5)
                    }
                } else {
                    Color.clear.frame(width: 70, height: 98)
                }
            }
            .frame(height: 104)
            MonoLabel("Market · \(model.marketSize) face down", size: 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RadialGradient(colors: [JamboreeTheme.accent.opacity(0.12), .clear],
                           center: .center, startRadius: 0, endRadius: 180),
        )
        .clipShape(RoundedRectangle(cornerRadius: JamboreeRadius.hero, style: .continuous))
    }

    private var hand: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Your hand · \(model.hand.count)")
            let cols = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(model.hand, id: \.id) { card in
                    Button {
                        selectedCardId = (selectedCardId == card.id) ? nil : card.id
                    } label: {
                        bluffCardChip(card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selectedCardId == card.id ? JamboreeTheme.accent : Color.clear, lineWidth: 3),
                            )
                            .offset(y: selectedCardId == card.id ? -8 : 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var actionRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("Buy market") { model.send(["type": "buy"]) }
                    .buttonStyle(UbSecondaryButtonStyle())
                    .disabled(model.marketSize == 0).opacity(model.marketSize == 0 ? 0.5 : 1)
                Button("Sell selected (+2)") {
                    guard let cid = selectedCardId else { return }
                    model.send(["type": "sell", "cardId": cid]); selectedCardId = nil
                }
                .buttonStyle(UbSecondaryButtonStyle())
                .disabled(selectedCardId == nil).opacity(selectedCardId == nil ? 0.5 : 1)
            }
            let candidates = model.players.filter { $0.id != ctx.yourId }
            if !model.hand.isEmpty && !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel("Propose trade")
                    ForEach(candidates, id: \.id) { p in
                        Button("Trade with \(p.name) — offer selected") {
                            guard let cid = selectedCardId else { return }
                            model.send(["type": "propose_trade", "targetId": p.id, "cardId": cid])
                            selectedCardId = nil
                        }
                        .buttonStyle(UbSecondaryButtonStyle())
                        .disabled(selectedCardId == nil).opacity(selectedCardId == nil ? 0.5 : 1)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ubCard()
            }
        }
    }

    @ViewBuilder
    private func tradeView(_ t: BluffMarketGuestModel.Trade) -> some View {
        let imProposer = ctx.yourId == t.proposerId
        let imTarget = ctx.yourId == t.targetId
        let imParty = imProposer || imTarget
        let proposerName = model.players.first { $0.id == t.proposerId }?.name ?? "?"
        let targetName = model.players.first { $0.id == t.targetId }?.name ?? "?"
        VStack(spacing: 12) {
            MonoLabel("Trade · \(proposerName) ↔ \(targetName)", color: JamboreeTheme.accent)
            if !imParty {
                // Trades are private: onlookers see who's trading, never the cards.
                Text("\(proposerName) and \(targetName) are trading privately…")
                    .font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
            } else if t.revealed {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        MonoLabel(proposerName, size: 9)
                        if let c = t.proposerCard { bluffCardChip(c) }
                    }
                    Text("⇄").font(.title).foregroundStyle(JamboreeTheme.muted)
                    VStack(spacing: 4) {
                        MonoLabel(targetName, size: 9)
                        if let c = t.targetCard { bluffCardChip(c) }
                    }
                }
                if imParty {
                    let answered = imProposer ? t.proposerAccept != nil : t.targetAccept != nil
                    if answered {
                        Text("You answered. Waiting for the other side…")
                            .font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
                    } else {
                        HStack(spacing: 10) {
                            Button("Accept") { model.send(["type": "respond_trade", "accept": true]) }
                                .buttonStyle(UbPrimaryButtonStyle())
                            Button("Reject") { model.send(["type": "respond_trade", "accept": false]) }
                                .buttonStyle(UbSecondaryButtonStyle())
                        }
                        if !guaranteeUsedByMe(t) {
                            Button("Guarantee the trade") { model.send(["type": "guarantee"]) }
                                .buttonStyle(UbSecondaryButtonStyle())
                        }
                    }
                }
            } else {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        MonoLabel(proposerName, size: 9)
                        GridCardBack(width: 70).opacity(t.proposerCommitted ? 1.0 : 0.3)
                    }
                    Text("?").font(.title).foregroundStyle(JamboreeTheme.muted)
                    VStack(spacing: 4) {
                        MonoLabel(targetName, size: 9)
                        GridCardBack(width: 70).opacity(t.targetCommitted ? 1.0 : 0.3)
                    }
                }
                if imTarget && t.targetCardId == nil {
                    Text("\(proposerName) is proposing a trade. Commit a card to counter.")
                        .font(.system(size: 12)).foregroundStyle(.white)
                    Button("Commit selected") {
                        guard let cid = selectedCardId else { return }
                        model.send(["type": "counter_trade", "cardId": cid]); selectedCardId = nil
                    }
                    .buttonStyle(UbPrimaryButtonStyle())
                    .disabled(selectedCardId == nil).opacity(selectedCardId == nil ? 0.5 : 1)
                    Button("Decline") { model.send(["type": "decline_trade"]) }
                        .buttonStyle(UbSecondaryButtonStyle())
                } else {
                    Text("\(proposerName) committed. Waiting for \(targetName) to counter…")
                        .font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
                    if imProposer {
                        Button("Cancel proposal") { model.send(["type": "decline_trade"]) }
                            .buttonStyle(UbSecondaryButtonStyle())
                    }
                }
            }
            if t.proposerGuarantee || t.targetGuarantee {
                MonoLabel("Guarantee invoked — trade forced", size: 9, color: JamboreeTheme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .ubCard(radius: JamboreeRadius.panel,
                fill: JamboreeTheme.accentSoft, stroke: JamboreeTheme.accentLine)
    }

    private func guaranteeUsedByMe(_ t: BluffMarketGuestModel.Trade) -> Bool {
        if ctx.yourId == t.proposerId && t.proposerGuarantee { return true }
        if ctx.yourId == t.targetId && t.targetGuarantee { return true }
        return model.players.first { $0.id == ctx.yourId }?.guaranteeUsed ?? false
    }

    @ViewBuilder private var scoringView: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Final scores · pending host reveal", color: JamboreeTheme.accent)
            VStack(spacing: 8) {
                ForEach(model.scoreRows, id: \.id) { r in
                    HStack {
                        Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("\(r.total)\(r.hasBomb ? " 💣" : "")")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .ubCard(radius: JamboreeRadius.row)
                }
            }
            Text("Waiting for the host…").font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
        }
    }

    @ViewBuilder private var overView: some View {
        let winner = model.players.first { $0.id == model.winnerId }
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Game over", color: JamboreeTheme.accent)
            Text("\(winner?.name ?? "?") wins")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
        }
        VStack(spacing: 8) {
            ForEach(model.scoreRows.sorted(by: { $0.total > $1.total }), id: \.id) { r in
                HStack(spacing: 12) {
                    Avatar(name: r.name, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name + (r.id == model.winnerId ? " 🏆" : "") + (r.hasBomb ? " 💣" : ""))
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        MonoLabel("sum \(r.sum) + coins \(r.coins)", size: 9, color: JamboreeTheme.faint)
                    }
                    Spacer()
                    Text("\(r.total)").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                }
                .padding(.vertical, 10).padding(.horizontal, 14)
                .ubCard(radius: JamboreeRadius.row)
            }
        }
    }

    @ViewBuilder
    private func bluffCardChip(_ c: BluffMarketGuestModel.Card) -> some View {
        switch c.kind {
        case "bomb":
            BluffBombCard(width: 80)
        case "wildcard":
            BluffPointCard(value: 0, width: 80)
        default:
            BluffPointCard(value: c.value, width: 80)
        }
    }

    private var isMyTurn: Bool { model.currentId == ctx.yourId }
    private var currentName: String {
        model.players.first { $0.id == model.currentId }?.name ?? ""
    }
}

@MainActor
final class BluffMarketGuestModel: ObservableObject {
    struct Player: Identifiable {
        let id: String; let name: String; let isHost: Bool
        let handCount: Int; let coins: Int; let turnsTaken: Int
        let guaranteeUsed: Bool
    }
    struct Card: Identifiable, Hashable {
        let id: String; let kind: String; let value: Int; let label: String
    }
    struct Trade {
        let proposerId: String; let targetId: String
        let proposerCommitted: Bool; let targetCommitted: Bool
        let revealed: Bool
        let proposerGuarantee: Bool; let targetGuarantee: Bool
        let proposerAccept: Bool?; let targetAccept: Bool?
        let proposerCardId: String?; let targetCardId: String?
        let proposerCard: Card?; let targetCard: Card?
    }
    struct ScoreRow: Identifiable {
        let id: String; let name: String
        let total: Int; let sum: Int; let coins: Int; let hasBomb: Bool
    }

    @Published var players: [Player] = []
    @Published var phase: String = "lobby"
    @Published var hand: [Card] = []
    @Published var marketSize: Int = 0
    @Published var currentId: String?
    @Published var trade: Trade?
    @Published var lastEvent: String = ""
    @Published var turnsPerPlayer: Int = 5
    @Published var scoreRows: [ScoreRow] = []
    @Published var winnerId: String?
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
            players = arr.map { Player(
                id: $0["id"] as? String ?? "",
                name: $0["name"] as? String ?? "",
                isHost: $0["isHost"] as? Bool ?? false,
                handCount: 0, coins: 0, turnsTaken: 0, guaranteeUsed: false) }
            phase = "lobby"
        case "state":
            if let p = m["phase"] as? String { phase = p }
            if let arr = m["players"] as? [[String: Any]] {
                players = arr.map { Player(
                    id: $0["id"] as? String ?? "",
                    name: $0["name"] as? String ?? "",
                    isHost: false,
                    handCount: $0["handCount"] as? Int ?? 0,
                    coins: $0["coins"] as? Int ?? 0,
                    turnsTaken: $0["turnsTaken"] as? Int ?? 0,
                    guaranteeUsed: $0["guaranteeUsed"] as? Bool ?? false) }
            }
            marketSize = m["marketSize"] as? Int ?? marketSize
            currentId = m["currentId"] as? String
            lastEvent = m["lastEvent"] as? String ?? ""
            turnsPerPlayer = m["turnsPerPlayer"] as? Int ?? turnsPerPlayer
            if let t = m["trade"] as? [String: Any] {
                let pc = (t["proposerCard"] as? [String: Any]).map { parseCard($0) }
                let tc = (t["targetCard"] as? [String: Any]).map { parseCard($0) }
                trade = Trade(
                    proposerId: t["proposerId"] as? String ?? "",
                    targetId: t["targetId"] as? String ?? "",
                    proposerCommitted: t["proposerCommitted"] as? Bool ?? false,
                    targetCommitted: t["targetCommitted"] as? Bool ?? false,
                    revealed: t["revealed"] as? Bool ?? false,
                    proposerGuarantee: t["proposerGuarantee"] as? Bool ?? false,
                    targetGuarantee: t["targetGuarantee"] as? Bool ?? false,
                    proposerAccept: t["proposerAccept"] as? Bool,
                    targetAccept: t["targetAccept"] as? Bool,
                    proposerCardId: pc?.id,
                    targetCardId: tc?.id,
                    proposerCard: pc,
                    targetCard: tc)
            } else { trade = nil }
        case "hand":
            let cs = m["cards"] as? [[String: Any]] ?? []
            hand = cs.map { parseCard($0) }
        case "scores":
            scoreRows = parseRows(m["rows"])
        case "over":
            phase = "gameOver"
            winnerId = m["winnerId"] as? String
            scoreRows = parseRows(m["rows"])
        case "reset":
            phase = "lobby"; hand = []; trade = nil; marketSize = 0
            scoreRows = []; winnerId = nil; lastEvent = ""
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

    private func parseCard(_ o: [String: Any]) -> Card {
        Card(id: o["id"] as? String ?? "",
             kind: o["kind"] as? String ?? "points",
             value: o["value"] as? Int ?? 0,
             label: o["label"] as? String ?? "")
    }

    private func parseRows(_ raw: Any?) -> [ScoreRow] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.map {
            ScoreRow(id: $0["id"] as? String ?? "",
                     name: $0["name"] as? String ?? "",
                     total: $0["total"] as? Int ?? 0,
                     sum: $0["sum"] as? Int ?? 0,
                     coins: $0["coins"] as? Int ?? 0,
                     hasBomb: $0["hasBomb"] as? Bool ?? false)
        }
    }
}
