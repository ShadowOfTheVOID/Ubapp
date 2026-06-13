import Foundation

enum BureaucratPhase { case lobby, arguing, rebuttal, voting, roundOver, gameOver }

/// Why a round ended — drives the round-over copy on every client.
enum RoundEndReason { case loopholeTimeout, loopholeContradiction, loopholeVote, bureaucratSurvived, tokensExhausted }

/// Host-configurable knobs. Defaults reproduce the reference rules.
struct BureaucratOptions: Equatable {
    var targetScore: Int = 10
    var challengeTokens: Int = 2
    var rebuttalSeconds: Int = 20
    /// Consult the contradiction detector on each rebuttal. Only used when
    /// `judging` is "nli".
    var aiAssist: Bool = true
    /// Input method for rebuttal: "type" (default) or "speak" (voice).
    var rebuttalMode: String = "type"
    /// How a rebuttal is judged: "nli" (AI detector, default) or "vote" (the
    /// table votes whether the loophole beats the rebuttal).
    var judging: String = "nli"
}

final class BureaucratPlayer {
    let id: String
    let name: String
    let isHost: Bool
    var score: Int = 0
    init(id: String, name: String, isHost: Bool) {
        self.id = id; self.name = name; self.isHost = isHost
    }
}

/// What a policy-log line is. Drives styling on every client and, crucially,
/// what the contradiction detector is allowed to judge against.
/// - `request`  — the round's absurd task, seeded as line 0. Shown to anchor
///   play, but **never** fed to the detector: denying the request literally
///   contradicts it, so it can't count against the Bureaucrat.
/// - `denial`   — a binding ruling the Bureaucrat typed.
/// - `claim`    — the citizen's loophole argument when they challenge.
/// - `rebuttal` — the Bureaucrat's forced answer to a claim.
enum PolicyKind: String { case request, denial, claim, rebuttal }

/// One line in the binding policy log.
struct PolicyEntry {
    let text: String
    let kind: PolicyKind
    /// Who put this on record: the bureaucrat for denials/rebuttals, the
    /// challenging citizen for claims, nil for the seeded request.
    let authorId: String?
}

struct RoundOutcome {
    let bureaucratId: String
    let challengerId: String?
    let reason: RoundEndReason
    let task: String
}

/// Pure game logic for "The Bureaucrat". Mirrors `BureaucratEngine.kt`
/// state-for-state; the server adapter owns the rebuttal countdown and the
/// contradiction check, feeding both into the engine as explicit events so
/// this stays a deterministic, I/O-free state machine.
final class BureaucratEngine {
    private var rng: any RandomNumberGenerator

    private(set) var players: [String: BureaucratPlayer] = [:]
    /// Insertion order, mirroring Android's linkedMapOf so role rotation and
    /// seeded task selection match across platforms.
    private var playerOrder: [String] = []

    var phase: BureaucratPhase = .lobby
    var roundNumber: Int = 0
    var bureaucratId: String?
    var task: String?
    var winnerId: String?
    private(set) var options = BureaucratOptions()

    private(set) var policyLog: [PolicyEntry] = []
    private(set) var pendingChallenger: String?
    /// Table-vote ballots for the open challenge: voterId -> "loophole stands".
    private(set) var votes: [String: Bool] = [:]
    private(set) var tokens: [String: Int] = [:]
    private(set) var lastRound: RoundOutcome?

    private var rotation = 0
    /// Index of the previous round's task, so a task never repeats back-to-back.
    private var lastTaskIndex = -1

    private let surviveReward = 2
    private let loopholeReward = 3
    private let failPenalty = 1

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    // MARK: Lobby
    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> BureaucratPlayer {
        let p = BureaucratPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }

    func removePlayer(_ id: String) {
        guard phase == .lobby else { return }
        players[id] = nil
        playerOrder.removeAll { $0 == id }
    }

    var canStart: Bool { phase == .lobby && players.count >= 3 }

    func setOptions(_ o: BureaucratOptions) {
        guard phase == .lobby else { return }
        var c = o
        c.targetScore = min(max(o.targetScore, 3), 50)
        c.challengeTokens = min(max(o.challengeTokens, 1), 9)
        c.rebuttalSeconds = min(max(o.rebuttalSeconds, 5), 120)
        c.rebuttalMode = (o.rebuttalMode == "speak") ? "speak" : "type"
        c.judging = (o.judging == "vote") ? "vote" : "nli"
        options = c
    }

    var citizens: [BureaucratPlayer] {
        playerOrder.compactMap { players[$0] }.filter { $0.id != bureaucratId }
    }

    /// Citizens eligible to vote on the open challenge — everyone but the
    /// bureaucrat (already excluded) and the challenger, who are both biased.
    var voters: [BureaucratPlayer] { citizens.filter { $0.id != pendingChallenger } }

    func tokensFor(_ id: String) -> Int { tokens[id] ?? 0 }

    func start() {
        guard canStart else { return }
        rotation = 0
        for p in players.values { p.score = 0 }
        beginRound()
    }

    private func beginRound() {
        guard !playerOrder.isEmpty else { return }
        bureaucratId = playerOrder[rotation % playerOrder.count]
        // Pick a task, never repeating the previous round's so play stays varied.
        let count = BureaucratTasks.all.count
        let idx: Int
        if lastTaskIndex < 0 || count <= 1 {
            idx = Int.random(in: 0..<count, using: &rng)
        } else {
            let r = Int.random(in: 0..<(count - 1), using: &rng)
            idx = r >= lastTaskIndex ? r + 1 : r
        }
        lastTaskIndex = idx
        let chosen = BureaucratTasks.all[idx]
        task = chosen
        policyLog.removeAll()
        // Seed the request as line 0 so the task anchors the whole round and
        // every denial/claim reads against it on screen.
        policyLog.append(PolicyEntry(text: chosen, kind: .request, authorId: nil))
        pendingChallenger = nil
        votes.removeAll()
        tokens.removeAll()
        for c in citizens { tokens[c.id] = options.challengeTokens }
        roundNumber += 1
        phase = .arguing
    }

    // MARK: Arguing
    @discardableResult
    func addDenial(playerId: String, text: String) -> Bool {
        guard phase == .arguing, playerId == bureaucratId else { return false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        policyLog.append(PolicyEntry(text: t, kind: .denial, authorId: bureaucratId))
        return true
    }

    /// A citizen spends a token to challenge, stating the loophole `claim` they
    /// are exploiting. The claim joins the log and becomes part of what the
    /// Bureaucrat's rebuttal is judged against, so the contradiction is always
    /// grounded in something a citizen actually argued.
    @discardableResult
    func callLoophole(citizenId: String, claim: String) -> Bool {
        guard phase == .arguing, citizenId != bureaucratId, players[citizenId] != nil,
              tokensFor(citizenId) > 0 else { return false }
        let c = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return false }
        policyLog.append(PolicyEntry(text: c, kind: .claim, authorId: citizenId))
        pendingChallenger = citizenId
        phase = .rebuttal
        return true
    }

    /// The rebuttal always becomes binding policy. How it is judged depends on
    /// `options.judging`:
    ///  - "nli": `contradicts` is the detector's verdict — true hands the round
    ///    to the challenger.
    ///  - "vote": the engine moves to `.voting` and the table decides via
    ///    `castVote`; `contradicts` is ignored.
    @discardableResult
    func submitRebuttal(text: String, contradicts: Bool) -> Bool {
        guard phase == .rebuttal, let challenger = pendingChallenger else { return false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        policyLog.append(PolicyEntry(text: t, kind: .rebuttal, authorId: bureaucratId))
        if options.judging == "vote" {
            votes.removeAll()
            phase = .voting
            return true
        }
        if contradicts {
            awardLoophole(challenger, reason: .loopholeContradiction)
            return true
        }
        failedChallenge(challenger)
        return true
    }

    /// A voter rules on the open challenge: `stands` = "the loophole beats the
    /// rebuttal". Auto-tallies once every eligible voter has weighed in.
    @discardableResult
    func castVote(voterId: String, stands: Bool) -> Bool {
        guard phase == .voting, let challenger = pendingChallenger else { return false }
        guard voterId != bureaucratId, voterId != challenger, players[voterId] != nil else { return false }
        votes[voterId] = stands
        if votes.count >= voters.count { tallyVotes() }
        return true
    }

    /// Host breaks a stalled vote: tally with whoever has voted so far. Missing
    /// ballots count for the bureaucrat, so overturning needs a real majority.
    @discardableResult
    func forceTally() -> Bool {
        guard phase == .voting else { return false }
        tallyVotes()
        return true
    }

    private func tallyVotes() {
        guard let challenger = pendingChallenger else { return }
        let eligible = voters.count
        let stands = votes.values.filter { $0 }.count
        if stands * 2 > eligible {
            awardLoophole(challenger, reason: .loopholeVote)
        } else {
            failedChallenge(challenger)
        }
    }

    /// Shared tail for a defence the challenger lost (NLI or vote): burn a
    /// token, dock a point, and survive the bureaucrat once tokens run dry.
    private func failedChallenge(_ challenger: String) {
        tokens[challenger] = max(tokensFor(challenger) - 1, 0)
        if let p = players[challenger] { p.score = max(p.score - failPenalty, 0) }
        pendingChallenger = nil
        votes.removeAll()
        phase = .arguing
        if citizens.allSatisfy({ tokensFor($0.id) <= 0 }) {
            bureaucratSurvives(reason: .tokensExhausted)
        }
    }

    /// Server-owned timer elapsed with no rebuttal: the challenger wins.
    @discardableResult
    func rebuttalTimedOut() -> Bool {
        guard phase == .rebuttal, let challenger = pendingChallenger else { return false }
        awardLoophole(challenger, reason: .loopholeTimeout)
        return true
    }

    @discardableResult
    func bureaucratSurvives(reason: RoundEndReason = .bureaucratSurvived) -> Bool {
        guard phase == .arguing || phase == .rebuttal, let b = bureaucratId else { return false }
        players[b]?.score += surviveReward
        endRound(challenger: nil, reason: reason)
        return true
    }

    private func awardLoophole(_ challenger: String, reason: RoundEndReason) {
        players[challenger]?.score += loopholeReward
        endRound(challenger: challenger, reason: reason)
    }

    private func endRound(challenger: String?, reason: RoundEndReason) {
        lastRound = RoundOutcome(bureaucratId: bureaucratId!, challengerId: challenger,
                                 reason: reason, task: task ?? "")
        pendingChallenger = nil
        votes.removeAll()
        phase = .roundOver
    }

    @discardableResult
    func nextRound() -> Bool {
        guard phase == .roundOver else { return false }
        if let leader = playerOrder.compactMap({ players[$0] }).max(by: { $0.score < $1.score }),
           leader.score >= options.targetScore {
            winnerId = leader.id
            phase = .gameOver
            return true
        }
        rotation += 1
        beginRound()
        return true
    }

    func nextBureaucratId() -> String? {
        guard !playerOrder.isEmpty else { return nil }
        return playerOrder[(rotation + 1) % playerOrder.count]
    }
}

/// Absurd shared tasks. Kept identical to the Kotlin `TASKS`.
enum BureaucratTasks {
    static let all: [String] = [
        "Register my deceased goldfish as a co-signer on my mortgage.",
        "Renew my expired dragon-riding permit.",
        "Appeal the noise complaint filed against my thoughts.",
        "Claim a tax deduction for emotional damage caused by Mondays.",
        "Get a parking permit for a vehicle that exists only in my dreams.",
        "Officially change my legal name to a sound I can only hum.",
        "File for joint custody of an idea I shared with a coworker.",
        "Obtain a refund for a sunset that did not meet expectations.",
        "Register my houseplant as an emotional support colleague.",
        "Request planning permission to build a moat around my desk.",
        "Apply for a passport for my reflection.",
        "Report my shadow as a lost item.",
        "Get a permit to whistle indoors on a Tuesday.",
        "Have last Thursday officially declared null and void.",
        "License my sourdough starter as a registered dependent.",
        "Appeal gravity on the grounds of personal inconvenience.",
    ]
}
