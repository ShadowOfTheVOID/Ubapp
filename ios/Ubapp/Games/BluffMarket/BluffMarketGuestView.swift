import SwiftUI

/// Native guest UI for Bluff Market — wire protocol from `bluff_market_browser.html`.
struct BluffMarketGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = BluffMarketGuestModel()
    @State private var selectedCardId: String?
    @State private var tradeTargetId: String?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .center, spacing: 12) {
                        Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
                        switch model.phase {
                        case "lobby":    lobby
                        case "scoring":  scoringView
                        case "gameOver": overView
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
            .navigationTitle("Bluff Market")
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
        marketCard
        if !model.lastEvent.isEmpty {
            Text(model.lastEvent).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        if let t = model.trade { tradeView(t) }
        hand
        if model.trade == nil && isMyTurn && model.phase == "playing" {
            actionRow
        }
    }

    @ViewBuilder private var playersStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    VStack(spacing: 4) {
                        Text(p.name).font(.caption.bold())
                        Text("\(p.handCount) cards · \(p.coins)c").font(.caption2)
                        Text("turn \(p.turnsTaken)/\(model.turnsPerPlayer)").font(.caption2)
                            .foregroundStyle(.secondary)
                        if !p.guaranteeUsed { Text("Guar").font(.caption2).foregroundStyle(.yellow) }
                    }
                    .padding(8).frame(minWidth: 86)
                    .background(model.currentId == p.id ? Color.accentColor : Color.white.opacity(0.04))
                    .foregroundStyle(model.currentId == p.id ? .white : .primary)
                    .cornerRadius(8)
                }
            }
        }
    }

    @ViewBuilder private var marketCard: some View {
        GroupBox {
            VStack(spacing: 4) {
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
                Text("Market: \(model.marketSize) card\(model.marketSize == 1 ? "" : "s") face down")
                    .font(.subheadline)
                Text(isMyTurn ? "Your turn — Trade, Buy, or Sell" : "\(currentName)'s turn")
                    .font(.subheadline.bold())
                    .foregroundStyle(isMyTurn ? .green : .secondary)
            }.padding(.vertical, 4)
        }
    }

    @ViewBuilder private var hand: some View {
        GroupBox("Your hand (\(model.hand.count))") {
            let cols = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(model.hand, id: \.id) { card in
                    Button {
                        selectedCardId = (selectedCardId == card.id) ? nil : card.id
                    } label: {
                        bluffCardChip(card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedCardId == card.id ? Color.accentColor : Color.clear, lineWidth: 3)
                            )
                            .offset(y: selectedCardId == card.id ? -8 : 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var actionRow: some View {
        VStack(spacing: 8) {
            HStack {
                Button { model.send(["type": "buy"]) } label: {
                    Text("Buy market").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(model.marketSize == 0)
                Button {
                    guard let cid = selectedCardId else { return }
                    model.send(["type": "sell", "cardId": cid])
                    selectedCardId = nil
                } label: {
                    Text("Sell selected (+2)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(selectedCardId == nil)
            }
            GroupBox("Propose trade") {
                if model.hand.isEmpty {
                    Text("No cards to offer.").font(.caption).foregroundStyle(.secondary)
                } else {
                    let candidates = model.players.filter { $0.id != ctx.yourId }
                    if candidates.isEmpty {
                        Text("No-one to trade with.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(candidates, id: \.id) { p in
                                Button {
                                    guard let cid = selectedCardId else { return }
                                    model.send(["type": "propose_trade",
                                                "targetId": p.id, "cardId": cid])
                                    selectedCardId = nil
                                } label: {
                                    Text("Trade with \(p.name) (offer selected)")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(selectedCardId == nil)
                            }
                        }
                    }
                }
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
        GroupBox("Trade: \(proposerName) ↔ \(targetName)") {
            VStack(spacing: 8) {
                if t.revealed {
                    HStack(spacing: 16) {
                        VStack {
                            Text(proposerName).font(.caption)
                            if let c = t.proposerCard { bluffCardChip(c) }
                        }
                        Text("⇄").font(.title)
                        VStack {
                            Text(targetName).font(.caption)
                            if let c = t.targetCard { bluffCardChip(c) }
                        }
                    }
                    if imParty {
                        let answered = imProposer ? t.proposerAccept != nil : t.targetAccept != nil
                        if answered {
                            Text("You answered. Waiting for the other side…")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Button("Accept") { model.send(["type": "respond_trade", "accept": true]) }
                                    .buttonStyle(.borderedProminent).tint(.green)
                                Button("Reject") { model.send(["type": "respond_trade", "accept": false]) }
                                    .buttonStyle(.borderedProminent).tint(.red)
                                if !guaranteeUsedByMe(t) {
                                    Button("Guarantee") { model.send(["type": "guarantee"]) }
                                        .buttonStyle(.bordered).tint(.yellow)
                                }
                            }
                        }
                    }
                } else {
                    // Pre-reveal: show face-down placeholders so players can
                    // see who's committed without revealing the cards.
                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text(proposerName).font(.caption)
                            GridCardBack(width: 70)
                                .opacity(t.proposerCommitted ? 1.0 : 0.3)
                        }
                        Text("?").font(.title)
                        VStack(spacing: 4) {
                            Text(targetName).font(.caption)
                            GridCardBack(width: 70)
                                .opacity(t.targetCommitted ? 1.0 : 0.3)
                        }
                    }
                    if imTarget && t.targetCardId == nil {
                        Text("\(proposerName) is proposing a trade. Commit a card to counter.")
                            .font(.caption)
                        Button {
                            guard let cid = selectedCardId else { return }
                            model.send(["type": "counter_trade", "cardId": cid])
                            selectedCardId = nil
                        } label: {
                            Text("Commit selected").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCardId == nil)
                        Button("Decline") { model.send(["type": "decline_trade"]) }
                            .buttonStyle(.bordered)
                    } else {
                        Text("\(proposerName) committed. Waiting for \(targetName) to counter…")
                            .font(.caption).foregroundStyle(.secondary)
                        if imProposer {
                            Button("Cancel proposal") { model.send(["type": "decline_trade"]) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if t.proposerGuarantee || t.targetGuarantee {
                    Text("Guarantee invoked — trade will be forced.")
                        .font(.caption).foregroundStyle(.yellow)
                }
            }
        }
    }

    private func guaranteeUsedByMe(_ t: BluffMarketGuestModel.Trade) -> Bool {
        if ctx.yourId == t.proposerId && t.proposerGuarantee { return true }
        if ctx.yourId == t.targetId && t.targetGuarantee { return true }
        // Or already used my one-shot Guarantee earlier this round.
        return model.players.first { $0.id == ctx.yourId }?.guaranteeUsed ?? false
    }

    @ViewBuilder private var scoringView: some View {
        GroupBox("Final scores — pending host reveal") {
            ForEach(model.scoreRows, id: \.id) { r in
                HStack {
                    Text(r.name)
                    Spacer()
                    Text("\(r.total)\(r.hasBomb ? " 💣" : "")")
                        .font(.headline)
                }
            }
            Text("Waiting for the host…").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var overView: some View {
        let winner = model.players.first { $0.id == model.winnerId }
        GroupBox("Game over") {
            Text("\(winner?.name ?? "?") wins!").font(.title2.bold())
            ForEach(model.scoreRows.sorted(by: { $0.total > $1.total }), id: \.id) { r in
                HStack {
                    Text(r.name + (r.hasBomb ? " 💣" : "") + (r.id == model.winnerId ? " 🏆" : ""))
                    Spacer()
                    Text("\(r.total)  (sum \(r.sum) + coins \(r.coins))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func bluffCardChip(_ c: BluffMarketGuestModel.Card) -> some View {
        switch c.kind {
        case "bomb":
            BluffBombCard(width: 80)
        case "wildcard":
            // Wildcard reuses the bomb framing in magenta but with a "WILD"
            // hero label — the shared component set doesn't have one yet so
            // we render a minimal placeholder until the design lands.
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
