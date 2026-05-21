import SwiftUI

/// Native guest UI for President — wire protocol from `president_browser.html`.
struct PresidentGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = PresidentGuestModel()
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
                        case "swapping": swapping
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
            .navigationTitle("President")
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
        trickCard
        if !model.lastEvent.isEmpty {
            Text(model.lastEvent).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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
                        if p.finished { Text(rankLabel(p.rank)).font(.caption2).foregroundStyle(.yellow) }
                        else if model.passed.contains(p.id) { Text("passed").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .padding(8).frame(minWidth: 86)
                    .background(model.currentId == p.id ? Color.accentColor : Color.white.opacity(0.04))
                    .foregroundStyle(model.currentId == p.id ? .white : .primary)
                    .cornerRadius(8)
                }
            }
        }
    }

    @ViewBuilder private var trickCard: some View {
        GroupBox {
            VStack(spacing: 4) {
                Text("Round \(model.roundNumber)").font(.caption).foregroundStyle(.secondary)
                if let t = model.trick {
                    Text("Open trick: \(t.kind)\(t.length > 0 ? " (\(t.length))" : "")").font(.subheadline)
                    Text("Must beat power \(t.topPower)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(isMyTurn ? "Your lead — play anything" : "Awaiting lead")
                        .font(.subheadline.bold())
                }
                if let lp = model.lastPlay {
                    let pname = model.players.first { $0.id == lp.playerId }?.name ?? "?"
                    let cards = lp.cards.map { rankShort($0.rank) + suitGlyph($0.suit) }.joined(separator: " ")
                    Text("Last play: \(pname) — \(cards)").font(.caption)
                }
            }.padding(.vertical, 4)
        }
    }

    @ViewBuilder private var hand: some View {
        GroupBox("Your hand (\(model.hand.count))") {
            let cols = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(model.hand.enumerated()), id: \.offset) { _, card in
                    let key = "\(card.suit)-\(card.rank)"
                    Button {
                        if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
                    } label: {
                        cardChip(card)
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
        let picked = pickedCards()
        HStack {
            if isMyTurn {
                Button {
                    guard !picked.isEmpty else { return }
                    model.send(["type": "play",
                                "cards": picked.map { ["suit": $0.suit, "rank": $0.rank] }])
                    selected.removeAll()
                } label: {
                    Text("Play \(picked.count)").frame(maxWidth: .infinity)
                }
                .disabled(picked.isEmpty)
                .buttonStyle(.borderedProminent)
                if model.trick != nil {
                    Button {
                        model.send(["type": "pass"])
                        selected.removeAll()
                    } label: {
                        Text("Pass").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder private var swapping: some View {
        GroupBox("Round \(model.roundNumber) — Swap") {
            if model.swapPrompts.isEmpty {
                Text("Waiting for others to swap cards…").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.swapPrompts.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 4) {
                        if p.giverChooses {
                            Text("Give \(p.count) card\(p.count == 1 ? "" : "s") of your choice to \(p.toName)")
                                .font(.subheadline.bold())
                            Text("Pick \(p.count) below, then tap Send.").font(.caption).foregroundStyle(.secondary)
                            let picked = pickedCards()
                            Button {
                                guard picked.count == p.count else { return }
                                model.send(["type": "swap",
                                            "cards": picked.map { ["suit": $0.suit, "rank": $0.rank] }])
                                selected.removeAll()
                            } label: {
                                Text("Send \(picked.count)/\(p.count) → \(p.toName)").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(picked.count != p.count)
                        } else {
                            Text("Auto-sending your top \(p.count) card\(p.count == 1 ? "" : "s") to \(p.toName)")
                                .font(.subheadline)
                            Button {
                                model.send(["type": "swap", "cards": []])
                            } label: {
                                Text("Send best \(p.count) → \(p.toName)").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        if !model.swapPrompts.isEmpty { hand }
    }

    @ViewBuilder private var gameOver: some View {
        GroupBox("Round over") {
            ForEach(model.players.sorted { $0.finishOrder == 0 ? Int.max : $0.finishOrder
                                          < ($1.finishOrder == 0 ? Int.max : $1.finishOrder) },
                    id: \.id) { p in
                HStack {
                    Text("\(p.finishOrder == 0 ? "?" : String(p.finishOrder)). \(p.name)")
                    Spacer()
                    Text(rankLabel(p.rank)).foregroundStyle(.secondary).font(.footnote)
                }
            }
            Text("Waiting for the host to start the next round…")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func cardChip(_ c: PresidentGuestModel.Card) -> some View {
        if let suit = CardSuit.fromWire(c.suit) {
            NoirCardFace(rank: c.rank, suit: suit, width: 64)
        } else {
            GridCardBack(width: 64)
        }
    }

    private var isMyTurn: Bool { model.currentId == ctx.yourId }

    private func pickedCards() -> [PresidentGuestModel.Card] {
        model.hand.filter { selected.contains("\($0.suit)-\($0.rank)") }
    }
}

@MainActor
final class PresidentGuestModel: ObservableObject {
    struct Player: Identifiable {
        let id: String; let name: String; let isHost: Bool; let handCount: Int
        let rank: String; let finished: Bool; let finishOrder: Int
    }
    struct Card: Hashable { let suit: String; let rank: Int }
    struct TrickInfo { let kind: String; let length: Int; let topPower: Int; let leaderId: String }
    struct LastPlay { let playerId: String; let cards: [Card] }
    struct SwapPrompt { let toId: String; let toName: String; let count: Int; let giverChooses: Bool }

    @Published var players: [Player] = []
    @Published var phase: String = "lobby"
    @Published var hand: [Card] = []
    @Published var trick: TrickInfo?
    @Published var lastPlay: LastPlay?
    @Published var currentId: String?
    @Published var lastEvent: String = ""
    @Published var roundNumber: Int = 0
    @Published var swapPrompts: [SwapPrompt] = []
    @Published var passed: Set<String> = []
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
                handCount: 0, rank: "neutral", finished: false, finishOrder: 0
            )}
            phase = "lobby"
        case "state":
            if let p = m["phase"] as? String { phase = p }
            if let arr = m["players"] as? [[String: Any]] {
                players = arr.map { Player(
                    id: $0["id"] as? String ?? "",
                    name: $0["name"] as? String ?? "",
                    isHost: false,
                    handCount: $0["handCount"] as? Int ?? 0,
                    rank: $0["rank"] as? String ?? "neutral",
                    finished: $0["finished"] as? Bool ?? false,
                    finishOrder: $0["finishOrder"] as? Int ?? 0
                )}
            }
            currentId = m["currentId"] as? String
            lastEvent = m["lastEvent"] as? String ?? ""
            roundNumber = m["roundNumber"] as? Int ?? roundNumber
            if let t = m["trick"] as? [String: Any] {
                trick = TrickInfo(
                    kind: t["kind"] as? String ?? "",
                    length: t["length"] as? Int ?? 0,
                    topPower: t["topPower"] as? Int ?? 0,
                    leaderId: t["leaderId"] as? String ?? "")
            } else { trick = nil }
            if let lp = m["lastPlay"] as? [String: Any],
               let cs = lp["cards"] as? [[String: Any]] {
                lastPlay = LastPlay(playerId: lp["playerId"] as? String ?? "",
                    cards: cs.map { Card(suit: $0["suit"] as? String ?? "", rank: $0["rank"] as? Int ?? 0) })
            } else { lastPlay = nil }
            if let arr = m["passedThisTrick"] as? [String] {
                passed = Set(arr)
            }
        case "hand":
            let cs = m["cards"] as? [[String: Any]] ?? []
            hand = cs.map { Card(suit: $0["suit"] as? String ?? "",
                                  rank: $0["rank"] as? Int ?? 0) }
        case "swap_prompts":
            let arr = m["prompts"] as? [[String: Any]] ?? []
            swapPrompts = arr.map {
                SwapPrompt(toId: $0["toId"] as? String ?? "",
                           toName: $0["toName"] as? String ?? "",
                           count: $0["count"] as? Int ?? 0,
                           giverChooses: $0["giverChooses"] as? Bool ?? false)
            }
        case "over":
            phase = "gameOver"
            if let arr = m["rankings"] as? [[String: Any]] {
                let byId = Dictionary(uniqueKeysWithValues: arr.compactMap { row -> (String, [String: Any])? in
                    guard let id = row["id"] as? String else { return nil }
                    return (id, row)
                })
                players = players.map { existing in
                    var p = existing
                    if let row = byId[existing.id] {
                        p = Player(id: existing.id, name: existing.name, isHost: existing.isHost,
                                   handCount: existing.handCount,
                                   rank: row["rank"] as? String ?? "neutral",
                                   finished: true,
                                   finishOrder: row["finishOrder"] as? Int ?? 0)
                    }
                    return p
                }
            }
        case "reset":
            phase = "lobby"; hand = []; trick = nil; lastPlay = nil; passed = []
            swapPrompts = []; lastEvent = ""; roundNumber = 0
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
fileprivate func rankShort(_ r: Int) -> String {
    switch r { case 11: "J"; case 12: "Q"; case 13: "K"; case 14: "A"; default: "\(r)" }
}
fileprivate func rankLabel(_ r: String) -> String {
    switch r {
    case "president": return "President"
    case "vicePresident": return "VP"
    case "viceScum": return "Vice Scum"
    case "scum": return "Scum"
    default: return ""
    }
}
