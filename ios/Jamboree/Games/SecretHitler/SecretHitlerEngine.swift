import Foundation

enum SecretHitlerPhase: String {
    case lobby, nomination, election
    case presidentDiscard, chancellorEnact, vetoDecision
    case policyPeek, investigation, investigationReveal
    case specialElection, execution
    case gameOver
}

enum SecretHitlerRole: String { case liberal, fascist, hitler }
enum SecretHitlerParty: String { case liberal, fascist }
enum SecretHitlerPolicy: String { case liberal, fascist }
enum SecretHitlerWinner: String { case liberal, fascist }
enum SecretHitlerWinReason: String {
    case fiveLiberalPolicies, sixFascistPolicies, hitlerElectedChancellor, hitlerExecuted
}

extension SecretHitlerRole {
    var party: SecretHitlerParty { self == .liberal ? .liberal : .fascist }
}

final class SecretHitlerPlayer {
    let id: String
    let name: String
    let isHost: Bool
    var role: SecretHitlerRole?
    var alive: Bool = true
    init(id: String, name: String, isHost: Bool) {
        self.id = id; self.name = name; self.isHost = isHost
    }
}

/// Pure game logic for Secret Hitler — supports 5–10 players.
/// Network/UI lives in the server adapter and view; the engine never touches I/O.
final class SecretHitlerEngine {
    private var rng: any RandomNumberGenerator

    private(set) var players: [String: SecretHitlerPlayer] = [:]
    /// Stable seating order — president rotates along this list.
    private(set) var seatOrder: [String] = []

    var phase: SecretHitlerPhase = .lobby

    // Round state
    private(set) var presidentId: String?
    private(set) var chancellorNomineeId: String?
    private(set) var chancellorId: String?
    private(set) var previousPresidentId: String?
    private(set) var previousChancellorId: String?
    /// When a special-election president finishes their term, the rotation
    /// returns to the seat after this id.
    private(set) var specialElectionResumeAfter: String?

    private(set) var electionTracker: Int = 0
    private(set) var liberalPolicies: Int = 0
    private(set) var fascistPolicies: Int = 0
    private(set) var vetoUnlocked = false

    // Decks
    private(set) var drawPile: [SecretHitlerPolicy] = []
    private(set) var discardPile: [SecretHitlerPolicy] = []
    private(set) var presidentialHand: [SecretHitlerPolicy] = []
    private(set) var chancellorHand: [SecretHitlerPolicy] = []
    private(set) var vetoRequested = false

    // Voting / power state
    var electionVotes: [String: Bool] = [:]
    private(set) var lastElectionPassed: Bool?
    private(set) var lastEnactedPolicy: SecretHitlerPolicy?
    private(set) var lastEnactedByChaos = false
    private(set) var lastExecutedId: String?
    private(set) var peekedPolicies: [SecretHitlerPolicy] = []
    private(set) var pendingInvestigationId: String?
    private(set) var lastInvestigation: (subjectId: String, party: SecretHitlerParty)?
    private(set) var investigatedIds: Set<String> = []

    var winner: SecretHitlerWinner?
    var winReason: SecretHitlerWinReason?

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    // MARK: Lobby
    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> SecretHitlerPlayer {
        let p = SecretHitlerPlayer(id: id, name: name, isHost: isHost)
        players[id] = p
        if !seatOrder.contains(id) { seatOrder.append(id) }
        return p
    }

    func removePlayer(_ id: String) {
        guard phase == .lobby else { return }
        players[id] = nil
        seatOrder.removeAll { $0 == id }
    }

    var canStart: Bool { phase == .lobby && (5...10).contains(players.count) }

    var alive: [SecretHitlerPlayer] {
        seatOrder.compactMap { players[$0] }.filter { $0.alive }
    }

    func start() {
        guard canStart else { return }
        assignRoles()
        buildDeck()
        seatOrder = seatOrder.shuffled(using: &rng)
        presidentId = seatOrder.first
        phase = .nomination
    }

    private func assignRoles() {
        let n = seatOrder.count
        let liberalCount: Int = [5: 3, 6: 4, 7: 4, 8: 5, 9: 5, 10: 6][n] ?? 3
        let fascistCount = n - liberalCount - 1 // excludes Hitler
        var roles: [SecretHitlerRole] = Array(repeating: .liberal, count: liberalCount)
        roles += Array(repeating: .fascist, count: fascistCount)
        roles.append(.hitler)
        roles.shuffle(using: &rng)
        for (i, pid) in seatOrder.enumerated() { players[pid]?.role = roles[i] }
    }

    private func buildDeck() {
        var deck: [SecretHitlerPolicy] = Array(repeating: .liberal, count: 6)
                                       + Array(repeating: .fascist, count: 11)
        deck.shuffle(using: &rng)
        drawPile = deck
        discardPile = []
    }

    /// Fascists know each other & Hitler. Hitler additionally knows the
    /// fascists only in 5–6 player games (canonical rule).
    func knownAllies(for playerId: String) -> [String] {
        guard let me = players[playerId], let role = me.role else { return [] }
        let n = seatOrder.count
        switch role {
        case .liberal: return []
        case .fascist:
            return seatOrder.filter { id in
                guard id != playerId, let p = players[id], let r = p.role else { return false }
                return r == .fascist || r == .hitler
            }
        case .hitler:
            if n >= 7 { return [] }
            return seatOrder.filter { id in
                guard id != playerId, let p = players[id] else { return false }
                return p.role == .fascist
            }
        }
    }

    // MARK: Nomination
    func eligibleChancellorNominees() -> [SecretHitlerPlayer] {
        let aliveCount = alive.count
        return alive.filter { p in
            guard p.id != presidentId else { return false }
            if p.id == previousChancellorId { return false }
            if aliveCount > 5 && p.id == previousPresidentId { return false }
            return true
        }
    }

    @discardableResult
    func nominateChancellor(_ targetId: String) -> Bool {
        guard phase == .nomination,
              eligibleChancellorNominees().contains(where: { $0.id == targetId }) else { return false }
        chancellorNomineeId = targetId
        electionVotes.removeAll()
        phase = .election
        return true
    }

    // MARK: Election
    /// Returns true once every alive player has voted.
    @discardableResult
    func submitVote(voterId: String, ja: Bool) -> Bool {
        guard phase == .election,
              let v = players[voterId], v.alive else { return false }
        electionVotes[voterId] = ja
        return electionVotes.count >= alive.count
    }

    /// Resolves a finished vote. Returns whether the election passed.
    @discardableResult
    func resolveElection() -> Bool {
        guard phase == .election else { return false }
        let yes = electionVotes.values.filter { $0 }.count
        let no = electionVotes.values.filter { !$0 }.count
        let passed = yes > no
        lastElectionPassed = passed

        if passed {
            previousPresidentId = presidentId
            previousChancellorId = chancellorNomineeId
            chancellorId = chancellorNomineeId
            electionTracker = 0

            // Hitler-elected-chancellor win.
            if fascistPolicies >= 3,
               let cid = chancellorId, players[cid]?.role == .hitler {
                winner = .fascist
                winReason = .hitlerElectedChancellor
                phase = .gameOver
                return true
            }
            dealPresidentialHand()
            phase = .presidentDiscard
            return true
        } else {
            chancellorNomineeId = nil
            chancellorId = nil
            electionTracker += 1
            if electionTracker >= 3 {
                triggerChaos()
            } else {
                advancePresident()
                phase = .nomination
            }
            return false
        }
    }

    // MARK: Legislative
    private func dealPresidentialHand() {
        ensureDeckHasAtLeast(3)
        presidentialHand = Array(drawPile.prefix(3))
        drawPile.removeFirst(3)
    }

    @discardableResult
    func presidentDiscard(index: Int) -> Bool {
        guard phase == .presidentDiscard,
              presidentialHand.indices.contains(index) else { return false }
        var hand = presidentialHand
        discardPile.append(hand.remove(at: index))
        chancellorHand = hand
        presidentialHand = []
        vetoRequested = false
        phase = .chancellorEnact
        return true
    }

    @discardableResult
    func chancellorEnact(index: Int) -> Bool {
        guard phase == .chancellorEnact,
              chancellorHand.indices.contains(index) else { return false }
        var hand = chancellorHand
        let played = hand.remove(at: index)
        discardPile.append(contentsOf: hand)
        chancellorHand = []
        enact(policy: played, byChaos: false)
        return true
    }

    @discardableResult
    func chancellorRequestVeto() -> Bool {
        guard phase == .chancellorEnact, vetoUnlocked else { return false }
        vetoRequested = true
        phase = .vetoDecision
        return true
    }

    @discardableResult
    func presidentVetoResponse(confirm: Bool) -> Bool {
        guard phase == .vetoDecision else { return false }
        if confirm {
            discardPile.append(contentsOf: chancellorHand)
            chancellorHand = []
            vetoRequested = false
            // Veto counts as a failed government — advance the tracker.
            electionTracker += 1
            if electionTracker >= 3 {
                triggerChaos()
            } else {
                advancePresident()
                phase = .nomination
            }
        } else {
            vetoRequested = false
            phase = .chancellorEnact
        }
        return true
    }

    private func enact(policy: SecretHitlerPolicy, byChaos: Bool) {
        lastEnactedPolicy = policy
        lastEnactedByChaos = byChaos
        if policy == .liberal { liberalPolicies += 1 } else { fascistPolicies += 1 }
        if fascistPolicies >= 5 { vetoUnlocked = true }

        // Win checks first.
        if liberalPolicies >= 5 {
            winner = .liberal; winReason = .fiveLiberalPolicies; phase = .gameOver; return
        }
        if fascistPolicies >= 6 {
            winner = .fascist; winReason = .sixFascistPolicies; phase = .gameOver; return
        }

        if !byChaos, policy == .fascist, let power = presidentialPower() {
            enterPower(power)
        } else {
            advancePresident()
            phase = .nomination
        }
    }

    /// Canonical Secret Hitler board powers, by player count + fascist track position.
    enum Power { case peek, investigate, specialElection, execution }
    private func presidentialPower() -> Power? {
        switch seatOrder.count {
        case 5, 6:
            switch fascistPolicies {
            case 3: return .peek
            case 4, 5: return .execution
            default: return nil
            }
        case 7, 8:
            switch fascistPolicies {
            case 2: return .investigate
            case 3: return .specialElection
            case 4, 5: return .execution
            default: return nil
            }
        case 9, 10:
            switch fascistPolicies {
            case 1, 2: return .investigate
            case 3: return .specialElection
            case 4, 5: return .execution
            default: return nil
            }
        default: return nil
        }
    }

    private func enterPower(_ p: Power) {
        switch p {
        case .peek:
            ensureDeckHasAtLeast(3)
            peekedPolicies = Array(drawPile.prefix(3))
            phase = .policyPeek
        case .investigate:
            phase = .investigation
        case .specialElection:
            phase = .specialElection
        case .execution:
            phase = .execution
        }
    }

    // MARK: Powers
    @discardableResult
    func acknowledgePeek() -> Bool {
        guard phase == .policyPeek else { return false }
        peekedPolicies = []
        advancePresident()
        phase = .nomination
        return true
    }

    /// President investigates a target — they may not investigate themselves
    /// or anyone already investigated this game.
    func investigationTargets() -> [SecretHitlerPlayer] {
        alive.filter { $0.id != presidentId && !investigatedIds.contains($0.id) }
    }

    @discardableResult
    func investigate(targetId: String) -> Bool {
        guard phase == .investigation,
              let t = players[targetId], t.alive,
              t.id != presidentId, !investigatedIds.contains(targetId) else { return false }
        pendingInvestigationId = targetId
        lastInvestigation = (targetId, t.role?.party ?? .liberal)
        investigatedIds.insert(targetId)
        phase = .investigationReveal
        return true
    }

    @discardableResult
    func acknowledgeInvestigation() -> Bool {
        guard phase == .investigationReveal else { return false }
        pendingInvestigationId = nil
        advancePresident()
        phase = .nomination
        return true
    }

    /// Special election: the named player becomes the next president for one
    /// round, then the rotation returns to the seat after the original.
    @discardableResult
    func callSpecialElection(targetId: String) -> Bool {
        guard phase == .specialElection,
              let t = players[targetId], t.alive, t.id != presidentId else { return false }
        specialElectionResumeAfter = presidentId
        presidentId = targetId
        chancellorNomineeId = nil
        chancellorId = nil
        phase = .nomination
        return true
    }

    /// President executes a player. Killing Hitler ends the game (Liberals win).
    func executionTargets() -> [SecretHitlerPlayer] {
        alive.filter { $0.id != presidentId }
    }

    @discardableResult
    func executePlayer(targetId: String) -> Bool {
        guard phase == .execution,
              let t = players[targetId], t.alive, t.id != presidentId else { return false }
        t.alive = false
        lastExecutedId = targetId
        if t.role == .hitler {
            winner = .liberal; winReason = .hitlerExecuted; phase = .gameOver
            return true
        }
        // If the executed player was the previous chancellor/president, those
        // term limits no longer constrain — the canonical rule treats dead
        // players as not term-limiting.
        if previousChancellorId == targetId { previousChancellorId = nil }
        if previousPresidentId == targetId { previousPresidentId = nil }
        advancePresident()
        phase = .nomination
        return true
    }

    // MARK: Rotation / chaos
    private func advancePresident() {
        if let resume = specialElectionResumeAfter {
            specialElectionResumeAfter = nil
            presidentId = nextAlive(after: resume)
        } else if let p = presidentId {
            presidentId = nextAlive(after: p)
        }
        chancellorNomineeId = nil
        chancellorId = nil
    }

    private func nextAlive(after id: String) -> String? {
        guard let idx = seatOrder.firstIndex(of: id) else { return alive.first?.id }
        let n = seatOrder.count
        for offset in 1...n {
            let candidate = seatOrder[(idx + offset) % n]
            if let p = players[candidate], p.alive { return candidate }
        }
        return nil
    }

    private func triggerChaos() {
        ensureDeckHasAtLeast(1)
        let top = drawPile.removeFirst()
        enact(policy: top, byChaos: true)
        if phase == .gameOver { return }
        electionTracker = 0
        previousChancellorId = nil
        previousPresidentId = nil
        // `enact` already advanced the president because powers are skipped on chaos.
    }

    private func ensureDeckHasAtLeast(_ k: Int) {
        if drawPile.count >= k { return }
        var combined = drawPile + discardPile
        combined.shuffle(using: &rng)
        drawPile = combined
        discardPile = []
    }
}
