import Foundation

/// Standard 52-card deck used by Cheat. Distinct from `CrazyEights`'s
/// `Card`/`Suit` so the two engines stay independent.
enum CheatSuit: String, CaseIterable {
    case clubs, diamonds, hearts, spades
    var short: String {
        switch self { case .clubs: "C"; case .diamonds: "D"; case .hearts: "H"; case .spades: "S" }
    }
    var glyph: String {
        switch self { case .clubs: "♣"; case .diamonds: "♦"; case .hearts: "♥"; case .spades: "♠" }
    }
    var isRed: Bool { self == .diamonds || self == .hearts }
}

struct CheatCard: Hashable {
    let suit: CheatSuit
    /// 1..13 where 1 = Ace, 11 = J, 12 = Q, 13 = K.
    let rank: Int

    var rankShort: String {
        switch rank { case 1: "A"; case 11: "J"; case 12: "Q"; case 13: "K"; default: "\(rank)" }
    }
    var id: String { "\(suit.short)\(rank)" }
    var display: String { "\(rankShort)\(suit.glyph)" }
}

func cheatStandardDeck() -> [CheatCard] {
    CheatSuit.allCases.flatMap { s in (1...13).map { CheatCard(suit: s, rank: $0) } }
}

enum CheatPhase { case lobby, playing, pendingWin, gameOver }

/// Host-configurable house rules.
struct CheatOptions: Equatable {
    /// When true, the active player may claim *any* rank rather than the
    /// next rank in sequence. More chaos, less strategy.
    var freeClaim: Bool = false
}

/// The currently-open play that any other player can call BS on. Cards
/// are face-down in the pile but the engine remembers their actual values
/// so calling BS can resolve correctly.
struct CheatLastPlay {
    let playerId: String
    let claimedRank: Int
    let actualCards: [CheatCard]
    var count: Int { actualCards.count }
}

/// Result of the most recent BS call, surfaced to clients so they can
/// reveal the cards briefly.
struct CheatReveal {
    let callerId: String
    let accusedId: String
    let claimedRank: Int
    let cards: [CheatCard]
    let truthful: Bool
    /// Player id that picks up the pile.
    let loserId: String
}

final class CheatPlayer {
    let id: String, name: String, isHost: Bool
    var hand: [CheatCard] = []
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

/// Cheat (a.k.a. BS / I Doubt It).
///
/// Turn cycle:
///  * The active player plays one or more cards face-down and claims a
///    rank that matches `expectedRank` (or anything if `freeClaim`).
///  * Anyone except the player who just played can call BS until the
///    next play closes the window.
///  * Calling BS reveals the cards; the loser picks up everything.
///  * Playing your last card enters `pendingWin` — any other player can
///    still call BS or `acceptWin` to confirm the round.
final class CheatEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: CheatPlayer] = [:]
    private var playerOrder: [String] = []
    private(set) var order: [String] = []
    var phase: CheatPhase = .lobby
    private(set) var options = CheatOptions()

    /// Closed cards in the pile — value known to the engine, hidden to clients.
    var pile: [CheatCard] = []
    /// Currently open play; nil between plays / at game start.
    var lastPlay: CheatLastPlay?
    /// The reveal from the most recent BS call, kept until the next play
    /// so clients can flash it on screen.
    var lastReveal: CheatReveal?

    /// 1..13. Next rank that must be claimed (unless `freeClaim`).
    var expectedRank: Int = 1
    var currentIndex: Int = 0
    var winnerId: String?
    var lastEvent: String?

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    var current: CheatPlayer? { order.isEmpty ? nil : players[order[currentIndex]] }
    var canStart: Bool { phase == .lobby && (3...8).contains(players.count) }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> CheatPlayer {
        let p = CheatPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }
    func removePlayer(_ id: String) {
        if phase == .lobby { players[id] = nil; playerOrder.removeAll { $0 == id } }
    }

    func setOptions(_ o: CheatOptions) {
        guard phase == .lobby else { return }
        options = o
    }

    func start() {
        guard canStart else { return }
        let deck = cheatStandardDeck().shuffled(using: &rng)
        order = playerOrder.shuffled(using: &rng)
        for p in players.values { p.hand.removeAll() }
        for (i, c) in deck.enumerated() {
            let pid = order[i % order.count]
            players[pid]!.hand.append(c)
        }
        for p in players.values {
            p.hand.sort { ($0.rank, $0.suit.rawValue) < ($1.rank, $1.suit.rawValue) }
        }
        pile.removeAll()
        lastPlay = nil
        lastReveal = nil
        expectedRank = 1
        currentIndex = 0
        winnerId = nil
        phase = .playing
        lastEvent = "\(current!.name) starts — claim Aces"
    }

    /// Plays `cards` (must be in hand) from `playerId`, claiming
    /// `claimedRank` (1..13). Returns nil on success, error string otherwise.
    func play(playerId: String, cards: [CheatCard], claimedRank: Int) -> String? {
        guard phase == .playing || phase == .pendingWin else { return "not playing" }
        guard phase != .pendingWin else { return "round is pending — call BS or accept" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.id == current!.id else { return "not your turn" }
        guard !cards.isEmpty else { return "play at least one card" }
        guard (1...13).contains(claimedRank) else { return "bad rank" }
        if !options.freeClaim && claimedRank != expectedRank {
            return "must claim \(rankName(expectedRank))"
        }
        var remaining = p.hand
        for c in cards {
            guard let idx = remaining.firstIndex(of: c) else { return "card not in hand" }
            remaining.remove(at: idx)
        }
        // Close the previous open play into the pile so calls only apply
        // to the newest play.
        if let prev = lastPlay {
            pile.append(contentsOf: prev.actualCards)
        }
        p.hand = remaining
        lastPlay = CheatLastPlay(playerId: p.id, claimedRank: claimedRank, actualCards: cards)
        lastReveal = nil
        lastEvent = "\(p.name) claims \(cards.count) \(rankName(claimedRank))\(cards.count == 1 ? "" : "s")"
        if p.hand.isEmpty {
            phase = .pendingWin
            winnerId = p.id
            // Do NOT advance turn — round resolves once someone calls BS or accepts.
            return nil
        }
        advanceTurn()
        expectedRank = options.freeClaim ? expectedRank : nextRank(claimedRank)
        return nil
    }

    /// `callerId` calls BS on the current `lastPlay`. Returns nil on success.
    func callBs(callerId: String) -> String? {
        guard phase == .playing || phase == .pendingWin else { return "not playing" }
        guard let lp = lastPlay else { return "nothing to call" }
        guard players[callerId] != nil else { return "unknown caller" }
        if callerId == lp.playerId { return "can't BS your own play" }
        let truthful = lp.actualCards.allSatisfy { $0.rank == lp.claimedRank }
        let loserId = truthful ? callerId : lp.playerId
        let losingPlayer = players[loserId]!
        let accusedName = players[lp.playerId]!.name
        let callerName = players[callerId]!.name
        // Pick up: everything in pile + open play's cards.
        var pickup = pile
        pickup.append(contentsOf: lp.actualCards)
        losingPlayer.hand.append(contentsOf: pickup)
        losingPlayer.hand.sort { ($0.rank, $0.suit.rawValue) < ($1.rank, $1.suit.rawValue) }
        pile.removeAll()
        lastReveal = CheatReveal(callerId: callerId, accusedId: lp.playerId,
                                 claimedRank: lp.claimedRank, cards: lp.actualCards,
                                 truthful: truthful, loserId: loserId)
        lastPlay = nil
        let outcome = truthful
            ? "\(callerName) called BS on \(accusedName) — truthful. \(callerName) picks up \(pickup.count)."
            : "\(callerName) called BS on \(accusedName) — caught! \(accusedName) picks up \(pickup.count)."
        lastEvent = outcome
        if phase == .pendingWin {
            if truthful {
                // Winner survives the call — they actually win.
                phase = .gameOver
            } else {
                // Caught: revert the pending win.
                winnerId = nil
                phase = .playing
                // Turn passes to the player after the cheater.
                currentIndex = (indexOf(lp.playerId) + 1) % order.count
                expectedRank = options.freeClaim ? expectedRank : nextRank(lp.claimedRank)
            }
        } else {
            // In normal play, turn passes to the player after whoever picked up.
            currentIndex = (indexOf(loserId) + 1) % order.count
            // expectedRank already advanced when the play was made.
        }
        return nil
    }

    /// Used when phase == pendingWin: any non-winner can accept the win,
    /// closing the BS window and ending the round.
    func acceptWin(playerId: String) -> String? {
        guard phase == .pendingWin else { return "no pending win" }
        guard let wid = winnerId else { return "no winner" }
        if playerId == wid { return "winner can't accept their own win" }
        guard players[playerId] != nil else { return "unknown player" }
        phase = .gameOver
        lastEvent = "\(players[playerId]!.name) accepted \(players[wid]!.name)'s win"
        return nil
    }

    /// Skip the BS window without calling — only matters in `pendingWin`.
    /// Returns true if win was confirmed.
    func confirmPendingWin() -> Bool {
        guard phase == .pendingWin else { return false }
        phase = .gameOver
        return true
    }

    func reset() {
        phase = .lobby
        for p in players.values { p.hand.removeAll() }
        pile.removeAll(); lastPlay = nil; lastReveal = nil
        winnerId = nil; lastEvent = nil
        expectedRank = 1; currentIndex = 0
    }

    private func advanceTurn() {
        currentIndex = (currentIndex + 1) % order.count
    }
    private func indexOf(_ id: String) -> Int { order.firstIndex(of: id) ?? 0 }

    /// Aces (1) → 2 → 3 … → K (13) → Aces.
    func nextRank(_ r: Int) -> Int { (r % 13) + 1 }

    func rankName(_ r: Int) -> String {
        switch r {
        case 1: "Aces"
        case 11: "Jacks"
        case 12: "Queens"
        case 13: "Kings"
        default: "\(r)s"
        }
    }
}
