import Foundation

/// Custom-deck game where everyone holds 3 face-down cards, one is a
/// `-25` "Bomb", and the round is a tense trade-and-conceal exercise.
enum BluffMarketPhase { case lobby, playing, scoring, gameOver }

/// Card kind. `points` may be negative (Bomb). `id` is unique per card.
struct BluffCard: Hashable, Identifiable {
    let id: String
    let kind: Kind

    enum Kind: Hashable {
        case points(Int)
        case bomb(Int)        // negative
        case wildcard         // doubles when traded — variant
    }

    var points: Int {
        switch kind {
        case .points(let v): v
        case .bomb(let v): v
        case .wildcard: 0
        }
    }

    /// Short label for the card face.
    var label: String {
        switch kind {
        case .points(let v): "+\(v)"
        case .bomb: "BOMB"
        case .wildcard: "WILD"
        }
    }
}

/// Host-configurable house rules.
struct BluffMarketOptions: Equatable {
    /// Turns per player before scoring. Default 5 per spec.
    var turnsPerPlayer: Int = 5
    /// Two bombs instead of one (suggested for larger groups).
    var twoBombs: Bool = false
    /// Add one wildcard worth double whatever it's traded for.
    var wildcard: Bool = false
}

/// A trade in flight. Both players commit a card face-down, then both
/// reveal, then both press Accept (or Guarantee to force-complete).
final class BluffTrade {
    let proposerId: String
    let targetId: String
    var proposerCardId: String?
    var targetCardId: String?
    /// Either side may invoke Guarantee — both will be forced to accept.
    var proposerGuarantee = false
    var targetGuarantee = false
    /// Per-side accept/reject responses.
    var proposerAccept: Bool?
    var targetAccept: Bool?
    /// Once committed-and-revealed.
    var revealed: Bool { proposerCardId != nil && targetCardId != nil }
    init(proposer: String, target: String) {
        self.proposerId = proposer; self.targetId = target
    }
}

final class BluffPlayer {
    let id: String, name: String, isHost: Bool
    var hand: [BluffCard] = []
    /// Coins earned from selling to market (each sell = +2).
    var coins: Int = 0
    /// 5-turn counter; round ends when all players reach `turnsPerPlayer`.
    var turnsTaken: Int = 0
    /// Each player has one Guarantee per game.
    var guaranteeUsed: Bool = false
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

/// Pure Bluff Market engine.
final class BluffMarketEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: BluffPlayer] = [:]
    private var playerOrder: [String] = []
    private(set) var seating: [String] = []
    var phase: BluffMarketPhase = .lobby
    private(set) var options = BluffMarketOptions()

    /// Face-down market deck. Top is the last element.
    var market: [BluffCard] = []
    var currentIndex: Int = 0
    var activeTrade: BluffTrade?
    var lastEvent: String?
    /// Per-card bookkeeping so we can validate "card in hand" and reveal trades.
    /// Map id → card.
    var cardCatalog: [String: BluffCard] = [:]

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    var current: BluffPlayer? { seating.isEmpty ? nil : players[seating[currentIndex]] }
    var canStart: Bool { phase == .lobby && (3...6).contains(players.count) }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> BluffPlayer {
        let p = BluffPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }
    func removePlayer(_ id: String) {
        if phase == .lobby { players[id] = nil; playerOrder.removeAll { $0 == id } }
    }

    func setOptions(_ o: BluffMarketOptions) {
        guard phase == .lobby else { return }
        var clamped = o
        clamped.turnsPerPlayer = max(2, min(o.turnsPerPlayer, 8))
        options = clamped
    }

    /// Build a deck appropriate for player count.
    /// 3p uses a slightly trimmed deck, 5p uses spec, 6p adds a few extras.
    private func buildDeck() -> [BluffCard] {
        // Counts: (value, copies).
        let n = players.count
        // Base distribution from spec for 5 players.
        var spec: [(Int, Int)] = [
            (1, 4), (2, 4), (5, 3), (10, 2), (15, 2), (20, 1),
        ]
        if n <= 3 { spec = [(1, 3), (2, 3), (5, 2), (10, 1), (15, 1), (20, 1)] }
        else if n == 4 { spec = [(1, 3), (2, 3), (5, 3), (10, 2), (15, 1), (20, 1)] }
        else if n >= 6 { spec = [(1, 5), (2, 5), (5, 3), (10, 3), (15, 2), (20, 1)] }
        var cards: [BluffCard] = []
        var seq = 0
        for (v, copies) in spec {
            for _ in 0..<copies {
                seq += 1
                cards.append(BluffCard(id: "P\(v)-\(seq)", kind: .points(v)))
            }
        }
        let bombCount = options.twoBombs ? 2 : 1
        for i in 0..<bombCount {
            cards.append(BluffCard(id: "B-\(i + 1)", kind: .bomb(-25)))
        }
        if options.wildcard {
            cards.append(BluffCard(id: "W-1", kind: .wildcard))
        }
        return cards.shuffled(using: &rng)
    }

    func start() {
        guard canStart else { return }
        seating = playerOrder.shuffled(using: &rng)
        for p in players.values {
            p.hand.removeAll(); p.coins = 0; p.turnsTaken = 0; p.guaranteeUsed = false
        }
        market.removeAll()
        cardCatalog.removeAll()
        activeTrade = nil
        let deck = buildDeck()
        for c in deck { cardCatalog[c.id] = c }
        var ix = 0
        for _ in 0..<3 {
            for pid in seating {
                if ix < deck.count {
                    players[pid]!.hand.append(deck[ix]); ix += 1
                }
            }
        }
        // Remaining go to market.
        while ix < deck.count { market.append(deck[ix]); ix += 1 }
        currentIndex = 0
        phase = .playing
        lastEvent = "Round started — \(current!.name) goes first"
    }

    /// Buy the top market card into the current player's hand. Returns nil on success.
    func buyFromMarket(playerId: String) -> String? {
        guard phase == .playing else { return "not playing" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.id == current!.id else { return "not your turn" }
        guard activeTrade == nil else { return "trade in flight" }
        guard !market.isEmpty else { return "market is empty" }
        let c = market.removeLast()
        p.hand.append(c)
        finishTurn(p)
        lastEvent = "\(p.name) bought from the market"
        return nil
    }

    /// Sell one of your cards to the market (face-down). Earn 2 coins.
    func sellToMarket(playerId: String, cardId: String) -> String? {
        guard phase == .playing else { return "not playing" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.id == current!.id else { return "not your turn" }
        guard activeTrade == nil else { return "trade in flight" }
        guard let idx = p.hand.firstIndex(where: { $0.id == cardId }) else { return "card not in hand" }
        let c = p.hand.remove(at: idx)
        market.append(c)
        p.coins += 2
        finishTurn(p)
        lastEvent = "\(p.name) sold to the market for 2"
        return nil
    }

    /// Propose a trade with `targetId`, offering a specific card.
    func proposeTrade(playerId: String, targetId: String, cardId: String) -> String? {
        guard phase == .playing else { return "not playing" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.id == current!.id else { return "not your turn" }
        guard activeTrade == nil else { return "trade in flight" }
        guard targetId != playerId else { return "can't trade with yourself" }
        guard players[targetId] != nil else { return "unknown target" }
        guard p.hand.contains(where: { $0.id == cardId }) else { return "card not in hand" }
        let trade = BluffTrade(proposer: playerId, target: targetId)
        trade.proposerCardId = cardId
        activeTrade = trade
        lastEvent = "\(p.name) proposes a trade with \(players[targetId]!.name)"
        return nil
    }

    /// Target commits their counter-card. Both cards become "revealed" once both committed.
    func counterTrade(playerId: String, cardId: String) -> String? {
        guard let t = activeTrade else { return "no active trade" }
        guard t.targetId == playerId else { return "not your trade" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.hand.contains(where: { $0.id == cardId }) else { return "card not in hand" }
        t.targetCardId = cardId
        lastEvent = "\(p.name) committed a counter-card"
        return nil
    }

    /// Either side may decline the trade outright before both have committed
    /// (or use it during the accept phase as "reject").
    func declineTrade(playerId: String) -> String? {
        guard let t = activeTrade else { return "no active trade" }
        guard playerId == t.targetId || playerId == t.proposerId else { return "not your trade" }
        let name = players[playerId]?.name ?? "?"
        activeTrade = nil
        // Cancelling a trade does NOT end the proposer's turn — they must
        // still buy, sell, or complete a trade, so a trade can't be used to
        // skip a turn.
        lastEvent = "\(name) cancelled the trade"
        return nil
    }

    /// Invoke The Guarantee. Either side can use this; it forces both sides
    /// to accept regardless of the response.
    func useGuarantee(playerId: String) -> String? {
        guard let t = activeTrade else { return "no active trade" }
        guard playerId == t.proposerId || playerId == t.targetId else { return "not your trade" }
        guard let p = players[playerId] else { return "unknown player" }
        if p.guaranteeUsed { return "guarantee already used" }
        p.guaranteeUsed = true
        if playerId == t.proposerId { t.proposerGuarantee = true } else { t.targetGuarantee = true }
        lastEvent = "\(p.name) invoked The Guarantee!"
        return nil
    }

    /// Both sides press Accept/Reject after reveal. If both accept (or
    /// either invoked Guarantee), the swap completes.
    func respondTrade(playerId: String, accept: Bool) -> String? {
        guard let t = activeTrade else { return "no active trade" }
        guard t.revealed else { return "wait for both sides to commit" }
        guard playerId == t.proposerId || playerId == t.targetId else { return "not your trade" }
        if playerId == t.proposerId { t.proposerAccept = accept }
        else { t.targetAccept = accept }
        if t.proposerAccept != nil && t.targetAccept != nil {
            settleTrade()
        }
        return nil
    }

    private func settleTrade() {
        guard let t = activeTrade else { return }
        let forced = t.proposerGuarantee || t.targetGuarantee
        let agreed = (t.proposerAccept == true && t.targetAccept == true) || forced
        let proposer = players[t.proposerId]!
        let target = players[t.targetId]!
        var completed = false
        if agreed, let pcid = t.proposerCardId, let tcid = t.targetCardId,
           let pIdx = proposer.hand.firstIndex(where: { $0.id == pcid }),
           let tIdx = target.hand.firstIndex(where: { $0.id == tcid }) {
            let pCard = proposer.hand.remove(at: pIdx)
            let tCard = target.hand.remove(at: tIdx)
            // Wildcard variant: trading a wildcard "doubles" the other side's value.
            // (Modeled as: swap proceeds normally; the wildcard's points are
            // computed at scoring as double the partner card's points if held.)
            // For simplicity here we just swap.
            proposer.hand.append(tCard)
            target.hand.append(pCard)
            lastEvent = "\(proposer.name) ⇆ \(target.name) — trade completed"
            completed = true
        }
        if !completed {
            lastEvent = "\(proposer.name) ⇆ \(target.name) — trade cancelled"
        }
        activeTrade = nil
        // Only a completed swap consumes the proposer's turn; a rejected
        // trade leaves it their turn so trading can't be used to skip.
        if completed { finishTurn(proposer) }
    }

    private func finishTurn(_ p: BluffPlayer) {
        p.turnsTaken += 1
        // Round ends after every player has reached turnsPerPlayer.
        if players.values.allSatisfy({ $0.turnsTaken >= options.turnsPerPlayer }) {
            phase = .scoring
            return
        }
        advanceTurn()
    }

    private func advanceTurn() {
        let n = seating.count
        for _ in 0..<n {
            currentIndex = (currentIndex + 1) % n
            // Skip nothing — all players act every round even if finished.
            return
        }
    }

    /// Compute final scores. Returns array of (playerId, total, breakdown).
    func score() -> [(id: String, name: String, total: Int, sum: Int, coins: Int, hasBomb: Bool)] {
        seating.compactMap { pid in
            guard let p = players[pid] else { return nil }
            let sum = p.hand.reduce(0) { $0 + $1.points }
            let hasBomb = p.hand.contains { if case .bomb = $0.kind { return true } else { return false } }
            let total = sum + p.coins
            return (id: pid, name: p.name, total: total, sum: sum, coins: p.coins, hasBomb: hasBomb)
        }
    }

    /// Move from scoring to gameOver.
    func finalize() {
        if phase == .scoring { phase = .gameOver }
    }

    func reset() {
        phase = .lobby
        for p in players.values {
            p.hand.removeAll(); p.coins = 0; p.turnsTaken = 0; p.guaranteeUsed = false
        }
        market.removeAll(); cardCatalog.removeAll()
        activeTrade = nil; lastEvent = nil; currentIndex = 0
    }
}
