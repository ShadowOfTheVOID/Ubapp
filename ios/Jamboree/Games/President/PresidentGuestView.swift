import SwiftUI

/// Native guest UI for President — wire protocol from `president_browser.html`.
struct PresidentGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = PresidentGuestModel()
    @State private var selected: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SeriesBanner(state: model.series)
                switch model.phase {
                case "lobby":    lobby
                case "swapping": swapping
                case "gameOver": gameOver
                default:         table
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("President")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .jamboreeChrome()
    }

    @ViewBuilder private var lobby: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("President · lobby", color: JamboreeTheme.accent)
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
            MonoLabel("President · round \(model.roundNumber)", color: JamboreeTheme.accent)
            Text(isMyTurn ? "Your turn" : "\(currentName)'s turn")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8)
                .foregroundStyle(isMyTurn ? JamboreeTheme.accent : .white)
            Text(model.trick == nil
                 ? (isMyTurn ? "Your lead — play anything." : "Awaiting the lead.")
                 : "Beat the open trick or pass.")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
        }
        playersStrip
        trickCard
        if !model.lastEvent.isEmpty { MonoLabel(model.lastEvent, size: 10, color: JamboreeTheme.muted) }
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
                            if p.finished {
                                MonoLabel(rankLabel(p.rank), size: 9, color: JamboreeTheme.accent)
                            } else if model.passed.contains(p.id) {
                                MonoLabel("passed", size: 9, color: JamboreeTheme.faint)
                            } else {
                                MonoLabel("\(p.handCount) cards", size: 9, color: JamboreeTheme.faint)
                            }
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

    private var trickCard: some View {
        VStack(spacing: 10) {
            MonoLabel(model.trick == nil ? "Open lead" : "To beat", size: 10, color: JamboreeTheme.accent)
            if let t = model.trick {
                Text("\(t.kind.capitalized)\(t.length > 0 ? " · \(t.length)" : "")")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                MonoLabel("Beat power \(t.topPower)", size: 9)
            } else {
                Text(isMyTurn ? "Play anything" : "Awaiting lead")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            }
            if let lp = model.lastPlay {
                let pname = model.players.first { $0.id == lp.playerId }?.name ?? "?"
                let cards = lp.cards.map { rankShort($0.rank) + suitGlyph($0.suit) }.joined(separator: " ")
                Text("\(pname): \(cards)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(JamboreeTheme.muted)
            }
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
            let cols = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(model.hand.enumerated()), id: \.offset) { _, card in
                    let key = "\(card.suit)-\(card.rank)"
                    Button {
                        if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
                    } label: {
                        cardChip(card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selected.contains(key) ? JamboreeTheme.accent : Color.clear, lineWidth: 3),
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
        if isMyTurn {
            HStack(spacing: 10) {
                if model.trick != nil {
                    Button("Pass") {
                        model.send(["type": "pass"])
                        selected.removeAll()
                    }.buttonStyle(UbSecondaryButtonStyle())
                }
                Button("Play \(picked.count)") {
                    guard !picked.isEmpty else { return }
                    model.send(["type": "play",
                                "cards": picked.map { ["suit": $0.suit, "rank": $0.rank] }])
                    selected.removeAll()
                }
                .buttonStyle(UbPrimaryButtonStyle())
                .disabled(picked.isEmpty)
                .opacity(picked.isEmpty ? 0.5 : 1)
            }
        }
    }

    private var currentName: String {
        model.players.first { $0.id == model.currentId }?.name ?? ""
    }

    @ViewBuilder private var swapping: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Round \(model.roundNumber) · swap", color: JamboreeTheme.accent)
            if model.swapPrompts.isEmpty {
                Text("Waiting for others to swap cards…")
                    .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
            } else {
                ForEach(Array(model.swapPrompts.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 8) {
                        if p.giverChooses {
                            Text("Give \(p.count) card\(p.count == 1 ? "" : "s") of your choice to \(p.toName)")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            Text("Pick \(p.count) below, then send.")
                                .font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
                            let picked = pickedCards()
                            Button("Send \(picked.count)/\(p.count) → \(p.toName)") {
                                guard picked.count == p.count else { return }
                                model.send(["type": "swap",
                                            "cards": picked.map { ["suit": $0.suit, "rank": $0.rank] }])
                                selected.removeAll()
                            }
                            .buttonStyle(UbPrimaryButtonStyle())
                            .disabled(picked.count != p.count)
                            .opacity(picked.count == p.count ? 1 : 0.5)
                        } else {
                            Text("Auto-sending your top \(p.count) card\(p.count == 1 ? "" : "s") to \(p.toName)")
                                .font(.system(size: 14)).foregroundStyle(.white)
                            Button("Send best \(p.count) → \(p.toName)") {
                                model.send(["type": "swap", "cards": []])
                            }.buttonStyle(UbPrimaryButtonStyle())
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ubCard(radius: JamboreeRadius.panel)
                }
            }
        }
        if !model.swapPrompts.isEmpty { hand }
    }

    @ViewBuilder private var gameOver: some View {
        let ranked = model.players.sorted { a, b in
            let ao = a.finishOrder == 0 ? Int.max : a.finishOrder
            let bo = b.finishOrder == 0 ? Int.max : b.finishOrder
            return ao < bo
        }
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Round over", color: JamboreeTheme.accent)
            Text("Final tiers")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
        }
        VStack(spacing: 8) {
            ForEach(ranked, id: \.id) { p in
                let isPres = p.rank == "president"
                HStack(spacing: 12) {
                    Text(p.finishOrder == 0 ? "?" : String(p.finishOrder))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(JamboreeTheme.faint).frame(width: 18)
                    Avatar(name: p.name, host: p.isHost, size: 30)
                    Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text(rankLabel(p.rank))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPres ? JamboreeTheme.onAccent : JamboreeTheme.muted)
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .background(isPres ? JamboreeTheme.accent : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 10).padding(.horizontal, 14)
                .ubCard(radius: JamboreeRadius.row)
            }
        }
        Text("Waiting for the host to start the next round…")
            .font(.system(size: 12)).foregroundStyle(JamboreeTheme.muted)
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
fileprivate func rankLabel(_ r: String) -> String {
    switch r {
    case "president": return "President"
    case "vicePresident": return "VP"
    case "viceScum": return "Vice Scum"
    case "scum": return "Scum"
    default: return ""
    }
}
