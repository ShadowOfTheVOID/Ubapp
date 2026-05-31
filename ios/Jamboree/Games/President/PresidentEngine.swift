import Foundation

/// Standard 52-card deck used by President. Distinct from `CrazyEights` /
/// `Cheat` so the engines stay independent. Card order low→high here is
///   3 4 5 6 7 8 9 10 J Q K A 2
/// with twos as the highest rank, so we store ranks as 2..14 and re-rank
/// in `power(_:)`.
enum PresSuit: String, CaseIterable {
    case clubs, diamonds, hearts, spades
    var short: String {
        switch self { case .clubs: "C"; case .diamonds: "D"; case .hearts: "H"; case .spades: "S" }
    }
    var glyph: String {
        switch self { case .clubs: "♣"; case .diamonds: "♦"; case .hearts: "♥"; case .spades: "♠" }
    }
    var isRed: Bool { self == .diamonds || self == .hearts }
}

struct PresCard: Hashable {
    let suit: PresSuit
    /// 2..14 where J=11, Q=12, K=13, A=14, 2 stays 2.
    let rank: Int

    var rankShort: String {
        switch rank { case 11: "J"; case 12: "Q"; case 13: "K"; case 14: "A"; default: "\(rank)" }
    }
    var id: String { "\(suit.short)\(rank)" }
    var display: String { "\(rankShort)\(suit.glyph)" }

    /// Power for trick-comparison: 3 (lowest) … 2 (highest).
    /// 3..10 keep their face value (3..10); J..K → 11..13; A → 14; 2 → 15.
    var power: Int {
        if rank == 2 { return 15 }
        return rank
    }
}

func presStandardDeck() -> [PresCard] {
    PresSuit.allCases.flatMap { s in (2...14).map { PresCard(suit: s, rank: $0) } }
}

enum PresidentPhase { case lobby, swapping, playing, gameOver }

enum PresRank: String, CaseIterable {
    case president, vicePresident, viceScum, scum, neutral

    var label: String {
        switch self {
        case .president: "President"
        case .vicePresident: "Vice President"
        case .viceScum: "Vice Scum"
        case .scum: "Scum"
        case .neutral: "Neutral"
        }
    }
}

/// One play in the current trick. Combinations: singles, pairs, triples,
/// quads, or runs of pairs (consecutive ranks; length even).
enum PresCombo: Equatable {
    case single, pair, triple, quad, runOfPairs(length: Int)
}

struct PresOptions: Equatable {
    /// President can announce a "house rule" each round (free-text).
    var allowHouseRules: Bool = false
    /// Playing 4-of-a-kind inverts card power for the rest of the trick.
    /// (No-op in our pure engine — recorded for UI display only.)
    var revolution: Bool = false
}

final class PresidentPlayer {
    let id: String, name: String, isHost: Bool
    var hand: [PresCard] = []
    var rank: PresRank = .neutral
    /// True if this player finished the round (placed all cards).
    var finished: Bool = false
    /// 1-based finishing order (1 = president). 0 means not finished.
    var finishOrder: Int = 0
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

/// The currently-open trick.
struct PresTrick {
    let combo: PresCombo
    let topPower: Int
    let leaderId: String
}

/// Pending card-swap action between rounds.
struct PresSwap {
    let fromId: String
    let toId: String
    /// Number of cards the `fromId` player must give.
    let count: Int
    /// True if the giver chooses (Pres back, VPs choose); false if it's
    /// the giver's "best" cards (Scum→Pres, VS→VP).
    let giverChooses: Bool
    /// Once selected by the giver, the actual cards.
    var cards: [PresCard]?
}

/// Pure President / Scum / Asshole engine.
final class PresidentEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: PresidentPlayer] = [:]
    private var playerOrder: [String] = []
    private(set) var seating: [String] = []
    var phase: PresidentPhase = .lobby
    private(set) var options = PresOptions()

    /// Current trick descriptor, nil between tricks.
    var trick: PresTrick?
    /// Players (in seating order, by id) who have passed during the current trick.
    var passedThisTrick: Set<String> = []
    /// Last play descriptor for UI (cards just played + by whom).
    var lastPlay: (playerId: String, cards: [PresCard], combo: PresCombo)?
    /// Finishing order (player ids in order they emptied their hand).
    var finishOrder: [String] = []
    var currentIndex: Int = 0
    var lastEvent: String?
    var roundNumber: Int = 0
    var pendingSwaps: [PresSwap] = []

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    var current: PresidentPlayer? { seating.isEmpty ? nil : players[seating[currentIndex]] }
    var canStart: Bool { phase == .lobby && (4...7).contains(players.count) }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> PresidentPlayer {
        let p = PresidentPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }
    func removePlayer(_ id: String) {
        if phase == .lobby { players[id] = nil; playerOrder.removeAll { $0 == id } }
    }

    func setOptions(_ o: PresOptions) {
        guard phase == .lobby else { return }
        options = o
    }

    /// Start the next round. On the first round, ranks haven't been
    /// assigned so we deal and the holder of 3♣ leads. Subsequent rounds
    /// open a swap phase before dealing-to-play.
    func start() {
        guard canStart else { return }
        seating = playerOrder.shuffled(using: &rng)
        for p in players.values { p.rank = .neutral; p.finished = false; p.finishOrder = 0; p.hand.removeAll() }
        finishOrder.removeAll()
        passedThisTrick.removeAll()
        trick = nil
        lastPlay = nil
        roundNumber = 1
        deal()
        // First round: 3-of-clubs leads.
        if let lead = seating.first(where: { id in players[id]!.hand.contains(PresCard(suit: .clubs, rank: 3)) }) {
            currentIndex = seating.firstIndex(of: lead)!
        } else {
            currentIndex = 0
        }
        phase = .playing
        lastEvent = "Round 1 — \(current!.name) leads with 3♣"
    }

    /// Begin a subsequent round: swap phase if ranks are set, else just deal+play.
    func startNextRound() {
        guard phase == .gameOver, !finishOrder.isEmpty else { return }
        assignRanks()
        roundNumber += 1
        for p in players.values { p.hand.removeAll(); p.finished = false; p.finishOrder = 0 }
        finishOrder.removeAll()
        trick = nil; lastPlay = nil; passedThisTrick.removeAll()
        deal()
        // Set up swap actions based on ranks.
        pendingSwaps = swapPlan()
        if pendingSwaps.isEmpty {
            // No swaps (e.g. 4-player game with no VPs — shouldn't happen)
            startTricksAfterSwaps()
        } else {
            phase = .swapping
            lastEvent = "Round \(roundNumber) — swap phase"
        }
    }

    /// Player provides a card selection for a pending swap. Returns nil on success.
    /// For "giver chooses" swaps the giver picks `count` cards; for "automatic
    /// best" swaps the engine ignores the input and uses the top cards.
    func submitSwap(fromId: String, cards: [PresCard]) -> String? {
        guard phase == .swapping else { return "not in swap phase" }
        guard let idx = pendingSwaps.firstIndex(where: { $0.fromId == fromId && $0.cards == nil })
        else { return "no pending swap for you" }
        let s = pendingSwaps[idx]
        let chosen: [PresCard]
        if s.giverChooses {
            guard cards.count == s.count else { return "give exactly \(s.count) card\(s.count == 1 ? "" : "s")" }
            chosen = cards
        } else {
            // Best == highest power.
            let sorted = players[fromId]!.hand.sorted { $0.power > $1.power }
            chosen = Array(sorted.prefix(s.count))
        }
        // Remove from giver, add to receiver.
        var giverHand = players[fromId]!.hand
        for c in chosen {
            guard let i = giverHand.firstIndex(of: c) else { return "card not in hand" }
            giverHand.remove(at: i)
        }
        players[fromId]!.hand = giverHand
        players[s.toId]!.hand.append(contentsOf: chosen)
        players[s.toId]!.hand.sort { $0.power < $1.power }
        players[fromId]!.hand.sort { $0.power < $1.power }
        pendingSwaps[idx].cards = chosen
        lastEvent = "\(players[fromId]!.name) gave \(chosen.count) card\(chosen.count == 1 ? "" : "s") to \(players[s.toId]!.name)"
        if pendingSwaps.allSatisfy({ $0.cards != nil }) {
            startTricksAfterSwaps()
        }
        return nil
    }

    private func startTricksAfterSwaps() {
        // President leads.
        if let pid = finishOrder.first, let i = seating.firstIndex(of: pid) {
            currentIndex = i
        } else {
            currentIndex = 0
        }
        phase = .playing
        lastEvent = "\(current!.name) (President) leads round \(roundNumber)"
        pendingSwaps.removeAll()
        finishOrder.removeAll()
        for p in players.values { p.finished = false; p.finishOrder = 0 }
    }

    /// Play a combination from `playerId`'s hand. Returns nil on success.
    func play(playerId: String, cards: [PresCard]) -> String? {
        guard phase == .playing else { return "not playing" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.id == current!.id else { return "not your turn" }
        guard !cards.isEmpty else { return "play at least one card" }
        // Must own all cards.
        var hand = p.hand
        for c in cards {
            guard let i = hand.firstIndex(of: c) else { return "card not in hand" }
            hand.remove(at: i)
        }
        guard let combo = classify(cards) else { return "invalid combination" }
        let power = comboPower(combo, cards: cards)
        if let t = trick {
            if !sameType(t.combo, combo) { return "must play \(describe(t.combo))" }
            if power <= t.topPower { return "must play higher than \(t.topPower)" }
            // First round constraint: opener must include 3♣ on round 1's first play.
        } else if roundNumber == 1 && lastPlay == nil
                  && p.hand.contains(PresCard(suit: .clubs, rank: 3))
                  && !cards.contains(PresCard(suit: .clubs, rank: 3)) {
            return "first play must include 3♣"
        }
        p.hand = hand
        trick = PresTrick(combo: combo, topPower: power, leaderId: trick?.leaderId ?? p.id)
        lastPlay = (p.id, cards, combo)
        passedThisTrick.removeAll() // Pass set tracks only players who passed since the last play.
        lastEvent = "\(p.name) played \(formatCards(cards)) (\(describe(combo)))"
        if p.hand.isEmpty {
            p.finished = true
            finishOrder.append(p.id)
            p.finishOrder = finishOrder.count
        }
        // If only one player still has cards, round ends.
        if remainingPlayers().count <= 1 {
            // Append any straggler.
            for sid in seating {
                if let pl = players[sid], !pl.finished {
                    pl.finished = true
                    finishOrder.append(pl.id)
                    pl.finishOrder = finishOrder.count
                }
            }
            assignRanks()
            phase = .gameOver
            lastEvent = "Round over"
            return nil
        }
        advanceTurn()
        return nil
    }

    /// Pass the current trick. Returns nil on success.
    func pass(playerId: String) -> String? {
        guard phase == .playing else { return "not playing" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.id == current!.id else { return "not your turn" }
        if trick == nil { return "lead — can't pass" }
        passedThisTrick.insert(p.id)
        lastEvent = "\(p.name) passed"
        // If every remaining player except the last leader has passed, the
        // trick closes and the last player to play leads.
        let alive = remainingPlayers().filter { !$0.finished }.map { $0.id }
        if let lp = lastPlay, alive.allSatisfy({ $0 == lp.playerId || passedThisTrick.contains($0) }) {
            // Trick closes.
            trick = nil
            passedThisTrick.removeAll()
            if let i = seating.firstIndex(of: lp.playerId), let player = players[lp.playerId], !player.finished {
                currentIndex = i
                lastEvent = "\(player.name) wins the trick and leads"
            } else {
                // Last player to play finished — next alive player leads.
                advanceTurn()
            }
            return nil
        }
        advanceTurn()
        return nil
    }

    func reset() {
        phase = .lobby
        for p in players.values { p.hand.removeAll(); p.rank = .neutral; p.finished = false; p.finishOrder = 0 }
        trick = nil; lastPlay = nil; passedThisTrick.removeAll()
        finishOrder.removeAll(); pendingSwaps.removeAll()
        currentIndex = 0; lastEvent = nil; roundNumber = 0
    }

    // MARK: - Internals

    private func deal() {
        let deck = presStandardDeck().shuffled(using: &rng)
        for (i, c) in deck.enumerated() {
            let pid = seating[i % seating.count]
            players[pid]!.hand.append(c)
        }
        for p in players.values { p.hand.sort { $0.power < $1.power } }
    }

    private func assignRanks() {
        guard !finishOrder.isEmpty else { return }
        let n = finishOrder.count
        for (i, id) in finishOrder.enumerated() {
            players[id]!.rank = rankFor(position: i, of: n)
            players[id]!.finishOrder = i + 1
        }
    }

    private func rankFor(position: Int, of total: Int) -> PresRank {
        if position == 0 { return .president }
        if position == total - 1 { return .scum }
        if total >= 4 && position == 1 { return .vicePresident }
        if total >= 4 && position == total - 2 { return .viceScum }
        return .neutral
    }

    /// Build the swap plan from current ranks. Scum→Pres = 2; VS→VP = 1.
    /// Both reverse exchanges are giverChooses (Pres picks back; VP picks back).
    private func swapPlan() -> [PresSwap] {
        var plan: [PresSwap] = []
        let pres = players.values.first { $0.rank == .president }
        let scum = players.values.first { $0.rank == .scum }
        let vp = players.values.first { $0.rank == .vicePresident }
        let vs = players.values.first { $0.rank == .viceScum }
        if let pres, let scum {
            plan.append(PresSwap(fromId: scum.id, toId: pres.id, count: 2,
                                  giverChooses: false, cards: nil))
            plan.append(PresSwap(fromId: pres.id, toId: scum.id, count: 2,
                                  giverChooses: true, cards: nil))
        }
        if let vp, let vs {
            plan.append(PresSwap(fromId: vs.id, toId: vp.id, count: 1,
                                  giverChooses: false, cards: nil))
            plan.append(PresSwap(fromId: vp.id, toId: vs.id, count: 1,
                                  giverChooses: true, cards: nil))
        }
        return plan
    }

    private func advanceTurn() {
        let n = seating.count
        for _ in 0..<n {
            currentIndex = (currentIndex + 1) % n
            let p = players[seating[currentIndex]]!
            if !p.finished { return }
        }
    }

    func remainingPlayers() -> [PresidentPlayer] {
        seating.compactMap { players[$0] }.filter { !$0.finished }
    }

    /// Classify a card group into a [PresCombo]. nil if not a legal play.
    func classify(_ cards: [PresCard]) -> PresCombo? {
        guard !cards.isEmpty else { return nil }
        let sorted = cards.sorted { $0.power < $1.power }
        let counts = Dictionary(grouping: sorted, by: { $0.rank }).mapValues { $0.count }
        if counts.count == 1 {
            switch sorted.count {
            case 1: return .single
            case 2: return .pair
            case 3: return .triple
            case 4: return .quad
            default: return nil
            }
        }
        // Run of pairs: every distinct rank has exactly 2 cards, ranks consecutive (by face value).
        if counts.values.allSatisfy({ $0 == 2 }) && counts.count >= 2 {
            let ranks = counts.keys.sorted()
            for i in 1..<ranks.count where ranks[i] != ranks[i-1] + 1 { return nil }
            return .runOfPairs(length: ranks.count)
        }
        return nil
    }

    /// Power for trick-beating: the highest power in the combo.
    func comboPower(_ combo: PresCombo, cards: [PresCard]) -> Int {
        cards.map { $0.power }.max() ?? 0
    }

    func sameType(_ a: PresCombo, _ b: PresCombo) -> Bool {
        switch (a, b) {
        case (.single, .single), (.pair, .pair), (.triple, .triple), (.quad, .quad):
            return true
        case let (.runOfPairs(la), .runOfPairs(lb)): return la == lb
        default: return false
        }
    }

    func describe(_ combo: PresCombo) -> String {
        switch combo {
        case .single: "single"
        case .pair: "pair"
        case .triple: "triple"
        case .quad: "four of a kind"
        case .runOfPairs(let len): "\(len) consecutive pairs"
        }
    }

    private func formatCards(_ cards: [PresCard]) -> String {
        cards.sorted { $0.power < $1.power }.map { $0.display }.joined(separator: " ")
    }
}
