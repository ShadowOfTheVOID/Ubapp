import Foundation

enum WerewolfPhase { case lobby, night, dayReveal, dayVote, hunterShot, gameOver }
enum WerewolfWinner { case werewolves, town }

/// Host-configurable knobs. Defaults reproduce the formula-driven game.
struct WerewolfOptions: Equatable {
    /// When non-nil, replaces the `players/5` formula at start time.
    var wolfCount: Int? = nil
    var seerEnabled: Bool = true
    var hunterEnabled: Bool = true
}

enum WerewolfRole: String {
    case werewolf, seer, hunter, villager
    var displayName: String {
        switch self {
        case .werewolf: "Werewolf"; case .seer: "Seer"
        case .hunter: "Hunter"; case .villager: "Villager"
        }
    }
    var tagline: String {
        switch self {
        case .werewolf: "Hunt the village. Coordinate with your pack at night."
        case .seer: "Each night, learn whether one player is a werewolf."
        case .hunter: "When you die, you take one player down with you."
        case .villager: "No special ability. Survive and vote wisely."
        }
    }
    var isTown: Bool { self != .werewolf }
    var hasNightAction: Bool { self == .werewolf || self == .seer }
}

final class WerewolfPlayer {
    let id: String, name: String, isHost: Bool
    var role: WerewolfRole?
    var alive = true
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

struct WerewolfNightOutcome { let killedId: String? }
struct WerewolfDayOutcome { let eliminatedId: String?; let tally: [String: Int] }
struct SeerResult { let seerId: String; let targetId: String; let isWerewolf: Bool }
struct HunterShot { let hunterId: String; let targetId: String }

final class WerewolfEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: WerewolfPlayer] = [:]
    /// Insertion order of player ids, mirroring Android's linkedMapOf so the
    /// seeded role assignment is identical across platforms (an unordered
    /// Swift Dictionary would otherwise shuffle a hash-randomized sequence).
    private var playerOrder: [String] = []
    var phase: WerewolfPhase = .lobby
    var day = 0
    var winner: WerewolfWinner?
    private(set) var options = WerewolfOptions()

    private var wolfVotes: [String: String] = [:]
    private var seerTarget: String?
    var dayVotes: [String: String?] = [:]

    var pendingHunterShooter: String?
    private var postHunterPhase: WerewolfPhase?

    var lastNight: WerewolfNightOutcome?
    var lastDay: WerewolfDayOutcome?
    var lastSeerResult: SeerResult?
    var hunterShotsThisRound: [HunterShot] = []

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> WerewolfPlayer {
        let p = WerewolfPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }
    func removePlayer(_ id: String) {
        if phase == .lobby { players[id] = nil; playerOrder.removeAll { $0 == id } }
    }
    var canStart: Bool { phase == .lobby && players.count >= 5 }

    /// Max wolves the current lobby supports (at least one villager remains).
    var maxWolfCount: Int { max(1, players.count - 1) }

    func setOptions(_ o: WerewolfOptions) {
        guard phase == .lobby else { return }
        var clamped = o
        if let c = o.wolfCount {
            clamped.wolfCount = max(1, min(c, maxWolfCount))
        }
        options = clamped
    }

    func start() {
        guard canStart else { return }
        let ids = playerOrder.shuffled(using: &rng)
        let formulaCount = max(1, min(ids.count - 3, ids.count / 5))
        let wolfCount = max(1, min(options.wolfCount ?? formulaCount, ids.count - 1))
        let includeHunter = options.hunterEnabled && ids.count >= 6
        var i = 0
        while i < wolfCount { players[ids[i]]!.role = .werewolf; i += 1 }
        if options.seerEnabled && i < ids.count {
            players[ids[i]]!.role = .seer; i += 1
        }
        if includeHunter && i < ids.count {
            players[ids[i]]!.role = .hunter; i += 1
        }
        while i < ids.count { players[ids[i]]!.role = .villager; i += 1 }
        phase = .night
        day = 1
    }

    var aliveWolves: [WerewolfPlayer] { players.values.filter { $0.alive && $0.role == .werewolf } }
    var aliveSeers: [WerewolfPlayer] { players.values.filter { $0.alive && $0.role == .seer } }
    var alive: [WerewolfPlayer] { players.values.filter { $0.alive } }
    var dead: [WerewolfPlayer] { players.values.filter { !$0.alive } }

    @discardableResult
    func submitWolfVote(voterId: String, targetId: String) -> Bool {
        guard phase == .night,
              let voter = players[voterId], voter.alive, voter.role == .werewolf,
              let target = players[targetId], target.alive, target.role != .werewolf
        else { return false }
        wolfVotes[voterId] = targetId
        return isNightReady()
    }
    @discardableResult
    func submitSeerTarget(seerId: String, targetId: String) -> Bool {
        guard phase == .night,
              let seer = players[seerId], seer.alive, seer.role == .seer,
              let target = players[targetId], target.alive, targetId != seerId
        else { return false }
        seerTarget = targetId
        return isNightReady()
    }
    private func isNightReady() -> Bool {
        let wolvesSubmitted = aliveWolves.allSatisfy { wolfVotes[$0.id] != nil }
        let seerSubmitted = aliveSeers.isEmpty || seerTarget != nil
        return wolvesSubmitted && seerSubmitted
    }

    @discardableResult
    func resolveNight() -> WerewolfNightOutcome {
        var tally: [String: Int] = [:]
        for t in wolfVotes.values { tally[t, default: 0] += 1 }
        let killTarget = uniqueMax(tally)
        if let st = seerTarget, let seer = aliveSeers.first, let target = players[st] {
            lastSeerResult = SeerResult(seerId: seer.id, targetId: target.id, isWerewolf: target.role == .werewolf)
        } else { lastSeerResult = nil }
        hunterShotsThisRound.removeAll()
        if let k = killTarget { killPlayer(k) }
        let out = WerewolfNightOutcome(killedId: killTarget)
        lastNight = out
        wolfVotes.removeAll(); seerTarget = nil
        if checkWin() { return out }
        if pendingHunterShooter != nil {
            postHunterPhase = .dayReveal; phase = .hunterShot
        } else { phase = .dayReveal }
        return out
    }

    func advanceToDayVote() {
        guard phase == .dayReveal else { return }
        dayVotes.removeAll()
        if checkWin() { return }
        phase = .dayVote
    }

    @discardableResult
    func submitDayVote(voterId: String, targetId: String?) -> Bool {
        guard phase == .dayVote, let voter = players[voterId], voter.alive else { return false }
        if let t = targetId {
            guard let p = players[t], p.alive else { return false }
        }
        dayVotes[voterId] = targetId
        return alive.allSatisfy { dayVotes[$0.id] != nil }
    }

    @discardableResult
    func resolveDay() -> WerewolfDayOutcome {
        var tally: [String: Int] = [:]
        for case let .some(t) in dayVotes.values { tally[t, default: 0] += 1 }
        let candidate = uniqueMax(tally)
        var eliminated: String?
        if let c = candidate, let max = tally[c], max * 2 > alive.count { eliminated = c }
        hunterShotsThisRound.removeAll()
        if let e = eliminated { killPlayer(e) }
        let out = WerewolfDayOutcome(eliminatedId: eliminated, tally: tally)
        lastDay = out
        if checkWin() { return out }
        if pendingHunterShooter != nil {
            postHunterPhase = .night; phase = .hunterShot
        } else {
            day += 1; phase = .night
        }
        return out
    }

    @discardableResult
    func submitHunterShot(hunterId: String, targetId: String) -> Bool {
        guard phase == .hunterShot, pendingHunterShooter == hunterId,
              let target = players[targetId], target.alive, targetId != hunterId
        else { return false }
        pendingHunterShooter = nil
        hunterShotsThisRound.append(HunterShot(hunterId: hunterId, targetId: targetId))
        killPlayer(targetId)
        if checkWin() { return true }
        if pendingHunterShooter != nil { return true }
        let returnTo = postHunterPhase ?? .dayReveal
        postHunterPhase = nil
        if returnTo == .night { day += 1 }
        phase = returnTo
        return true
    }

    private func killPlayer(_ id: String) {
        guard let p = players[id], p.alive else { return }
        p.alive = false
        if p.role == .hunter { pendingHunterShooter = id }
    }

    private func checkWin() -> Bool {
        let liveWolves = aliveWolves.count
        let liveTown = alive.filter { $0.role != .werewolf }.count
        if liveWolves == 0 { winner = .town; phase = .gameOver; return true }
        if liveWolves >= liveTown { winner = .werewolves; phase = .gameOver; return true }
        return false
    }

    private func uniqueMax(_ tally: [String: Int]) -> String? {
        var maxCount = 0, tied: [String] = []
        for (id, c) in tally {
            if c > maxCount { maxCount = c; tied = [id] }
            else if c == maxCount { tied.append(id) }
        }
        return tied.count == 1 ? tied[0] : nil
    }
}
