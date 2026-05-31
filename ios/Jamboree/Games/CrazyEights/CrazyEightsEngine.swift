import Foundation

enum Suit: String, CaseIterable {
    case clubs, diamonds, hearts, spades
    var short: String {
        switch self { case .clubs: "C"; case .diamonds: "D"; case .hearts: "H"; case .spades: "S" }
    }
    var glyph: String {
        switch self { case .clubs: "♣"; case .diamonds: "♦"; case .hearts: "♥"; case .spades: "♠" }
    }
    var isRed: Bool { self == .diamonds || self == .hearts }
}

struct Card: Hashable {
    let suit: Suit
    /// 2..14 (J=11, Q=12, K=13, A=14).
    let rank: Int

    var rankShort: String {
        switch rank { case 11: "J"; case 12: "Q"; case 13: "K"; case 14: "A"; default: "\(rank)" }
    }
    var id: String { "\(suit.short)\(rank)" }
    var display: String { "\(rankShort)\(suit.glyph)" }
}

func standardDeck() -> [Card] {
    Suit.allCases.flatMap { s in (2...14).map { Card(suit: s, rank: $0) } }
}

enum CrazyEightsPhase { case lobby, playing, gameOver }

/// Host-configurable house rules. Defaults reproduce the classic game.
struct CrazyEightsOptions: Equatable {
    /// When non-nil, overrides the player-count-based deal size (clamped 3...10).
    var startingHandSize: Int? = nil
    /// Playing a Jack skips the next player.
    var jackSkips: Bool = false
    /// Playing a Queen reverses turn direction.
    var queenReverses: Bool = false
    /// Playing a 2 forces the next player to draw two cards and lose their turn.
    var twosDrawTwo: Bool = false
}

final class CrazyEightsPlayer {
    let id: String, name: String, isHost: Bool
    var hand: [Card] = []
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

final class CrazyEightsEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: CrazyEightsPlayer] = [:]
    /// Insertion order of player ids, mirroring Android's linkedMapOf so the
    /// seeded deal/turn order is identical across platforms (an unordered
    /// Swift Dictionary would otherwise shuffle a hash-randomized sequence).
    private var playerOrder: [String] = []
    private var order: [String] = []
    /// Consecutive turns where the draw pile is exhausted and can't be
    /// replenished and the player can't act. A full lap of these ends the
    /// game so a blocked board doesn't loop forever.
    private var stalePasses = 0
    var phase: CrazyEightsPhase = .lobby
    private(set) var options = CrazyEightsOptions()

    var drawPile: [Card] = []
    var discardPile: [Card] = []
    /// Overrides top card suit when an 8 is played.
    var activeSuit: Suit?
    var currentIndex = 0
    var justDrew = false
    /// +1 for forward, -1 for reversed (when queenReverses is on).
    private var direction = 1
    var winnerId: String?
    var lastEvent: String?

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    var current: CrazyEightsPlayer? { order.isEmpty ? nil : players[order[currentIndex]] }
    var topCard: Card? { discardPile.last }
    var activeOrTopSuit: Suit { activeSuit ?? topCard!.suit }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> CrazyEightsPlayer {
        let p = CrazyEightsPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }
    func removePlayer(_ id: String) {
        if phase == .lobby { players[id] = nil; playerOrder.removeAll { $0 == id } }
    }
    var canStart: Bool { phase == .lobby && (2...8).contains(players.count) }

    func setOptions(_ o: CrazyEightsOptions) {
        guard phase == .lobby else { return }
        var clamped = o
        if let s = o.startingHandSize { clamped.startingHandSize = max(3, min(s, 10)) }
        options = clamped
    }

    func start() {
        guard canStart else { return }
        drawPile = standardDeck().shuffled(using: &rng)
        discardPile.removeAll()
        activeSuit = nil
        direction = 1
        let dealCount = options.startingHandSize ?? (players.count == 2 ? 7 : 5)
        stalePasses = 0
        order = playerOrder.shuffled(using: &rng)
        for _ in 0..<dealCount {
            for pid in order { players[pid]!.hand.append(drawPile.removeLast()) }
        }
        while let c = drawPile.popLast() {
            discardPile.append(c)
            if c.rank != 8 { break }
        }
        currentIndex = 0
        justDrew = false
        phase = .playing
        lastEvent = "\(current!.name) starts"
    }

    func canPlay(_ c: Card) -> Bool {
        guard let top = topCard else { return true }
        if c.rank == 8 { return true }
        if c.suit == activeOrTopSuit { return true }
        if c.rank == top.rank { return true }
        return false
    }

    /// Returns nil on success, an error message on failure.
    func playCard(playerId: String, card: Card, declaredSuit: Suit? = nil) -> String? {
        guard phase == .playing else { return "not playing" }
        guard let p = players[playerId] else { return "unknown player" }
        guard p.id == current!.id else { return "not your turn" }
        guard let idx = p.hand.firstIndex(of: card) else { return "card not in hand" }
        if !canPlay(card) { return "card does not match" }
        if card.rank == 8 && declaredSuit == nil { return "must declare a suit" }
        p.hand.remove(at: idx)
        discardPile.append(card)
        stalePasses = 0
        activeSuit = card.rank == 8 ? declaredSuit : nil
        justDrew = false
        // House-rule effects evaluated before turn advance.
        if options.queenReverses && card.rank == 12 && order.count > 2 { direction = -direction }
        let skipNext = options.jackSkips && card.rank == 11 && order.count > 2
        lastEvent = card.rank == 8
            ? "\(p.name) played \(card.display) → \(declaredSuit!.glyph)"
            : "\(p.name) played \(card.display)"
        if p.hand.isEmpty {
            phase = .gameOver
            winnerId = p.id
            return nil
        }
        advanceTurn()
        if skipNext { advanceTurn() }
        if options.twosDrawTwo && card.rank == 2 && order.count >= 2 {
            let victim = current!
            for _ in 0..<2 {
                if drawPile.isEmpty { reshuffle() }
                if !drawPile.isEmpty { victim.hand.append(drawPile.removeLast()) }
            }
            lastEvent = "\(victim.name) draws two and is skipped"
            advanceTurn()
        }
        return nil
    }

    @discardableResult
    func drawOne(playerId: String) -> Card? {
        guard phase == .playing, let p = players[playerId], p.id == current!.id else { return nil }
        if drawPile.isEmpty { reshuffle() }
        if drawPile.isEmpty {
            stalePasses += 1
            if stalePasses >= order.count {
                phase = .gameOver
                var best = order[0]
                for pid in order where players[pid]!.hand.count < players[best]!.hand.count { best = pid }
                winnerId = best
                lastEvent = "Stalemate — \(players[best]!.name) wins with the fewest cards"
                return nil
            }
            advanceTurn()
            return nil
        }
        let c = drawPile.removeLast()
        p.hand.append(c)
        stalePasses = 0
        lastEvent = "\(p.name) drew a card"
        if canPlay(c) {
            justDrew = true
            return c
        }
        justDrew = false
        advanceTurn()
        return c
    }

    func passAfterDraw(playerId: String) {
        guard phase == .playing, let p = players[playerId], p.id == current!.id, justDrew else { return }
        justDrew = false
        lastEvent = "\(p.name) passed"
        advanceTurn()
    }

    private func advanceTurn() {
        let n = order.count
        currentIndex = ((currentIndex + direction) % n + n) % n
        justDrew = false
    }

    private func reshuffle() {
        guard discardPile.count > 1 else { return }
        let top = discardPile.removeLast()
        drawPile.append(contentsOf: discardPile.shuffled(using: &rng))
        discardPile = [top]
    }

    func reset() {
        phase = .lobby
        drawPile.removeAll(); discardPile.removeAll()
        activeSuit = nil; currentIndex = 0; justDrew = false; direction = 1
        stalePasses = 0
        winnerId = nil; lastEvent = nil
        for p in players.values { p.hand.removeAll() }
    }
}
