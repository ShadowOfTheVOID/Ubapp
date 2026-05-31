import Foundation

enum MafiaPhase { case lobby, night, dayReveal, dayVote, gameOver }
enum MafiaWinner { case mafia, town }

/// Host-configurable knobs. Defaults reproduce the formula-driven game so
/// an unconfigured session plays exactly like before this struct existed.
struct MafiaOptions: Equatable {
    /// When non-nil, replaces the `players/4` formula at start time.
    var mafiaCount: Int? = nil
    var doctorEnabled: Bool = true
}

enum MafiaRole: String {
    case mafia, doctor, villager
    var displayName: String {
        switch self { case .mafia: "Mafia"; case .doctor: "Doctor"; case .villager: "Villager" }
    }
    var tagline: String {
        switch self {
        case .mafia: "Eliminate the town. Coordinate with your fellow mafia at night."
        case .doctor: "Save one player each night. You can self-save once per game."
        case .villager: "You have no special ability. Use your vote during the day."
        }
    }
    var isTown: Bool { self != .mafia }
    var hasNightAction: Bool { self == .mafia || self == .doctor }
}

final class MafiaPlayer {
    let id: String
    let name: String
    let isHost: Bool
    var role: MafiaRole?
    var alive: Bool = true
    init(id: String, name: String, isHost: Bool) {
        self.id = id; self.name = name; self.isHost = isHost
    }
}

struct NightOutcome { let killedId: String?; let savedId: String? }
struct DayOutcome { let eliminatedId: String?; let tally: [String: Int] }

/// Pure game logic. The server adapter is responsible for collecting
/// messages and feeding them in; the engine never touches network code.
final class MafiaEngine {
    private var rng: any RandomNumberGenerator

    private(set) var players: [String: MafiaPlayer] = [:]
    /// Insertion order of player ids, mirroring Android's linkedMapOf so the
    /// seeded role assignment is identical across platforms (an unordered
    /// Swift Dictionary would otherwise shuffle a hash-randomized sequence).
    private var playerOrder: [String] = []
    var phase: MafiaPhase = .lobby
    var day: Int = 0
    var winner: MafiaWinner?
    private(set) var options = MafiaOptions()

    private var mafiaVotes: [String: String] = [:]
    private var doctorTarget: String?
    private var doctorSelfSaveUsed = false

    var dayVotes: [String: String?] = [:]
    var lastNight: NightOutcome?
    var lastDay: DayOutcome?

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    // MARK: Lobby
    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> MafiaPlayer {
        let p = MafiaPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }

    func removePlayer(_ id: String) {
        guard phase == .lobby else { return }
        players[id] = nil
        playerOrder.removeAll { $0 == id }
    }

    var canStart: Bool { phase == .lobby && players.count >= 4 }

    /// Max evil players the current lobby can sustain (at least one villager
    /// must remain). Used to clamp `MafiaOptions.mafiaCount`.
    var maxMafiaCount: Int { max(1, players.count - 1) }

    func setOptions(_ o: MafiaOptions) {
        guard phase == .lobby else { return }
        var clamped = o
        if let c = o.mafiaCount {
            clamped.mafiaCount = max(1, min(c, maxMafiaCount))
        }
        options = clamped
    }

    func start() {
        guard canStart else { return }
        let ids = playerOrder.shuffled(using: &rng)
        let formulaCount = max(1, min(ids.count - 2, ids.count / 4))
        let mafiaCount = max(1, min(options.mafiaCount ?? formulaCount, ids.count - 1))
        var i = 0
        while i < mafiaCount { players[ids[i]]!.role = .mafia; i += 1 }
        if options.doctorEnabled && i < ids.count {
            players[ids[i]]!.role = .doctor; i += 1
        }
        while i < ids.count { players[ids[i]]!.role = .villager; i += 1 }
        phase = .night
        day = 1
    }

    // MARK: Night
    var aliveMafia: [MafiaPlayer] { players.values.filter { $0.alive && $0.role == .mafia } }
    var aliveDoctors: [MafiaPlayer] { players.values.filter { $0.alive && $0.role == .doctor } }
    var alive: [MafiaPlayer] { players.values.filter { $0.alive } }
    var dead: [MafiaPlayer] { players.values.filter { !$0.alive } }

    @discardableResult
    func submitMafiaVote(voterId: String, targetId: String) -> Bool {
        guard phase == .night,
              let voter = players[voterId], voter.alive, voter.role == .mafia,
              let target = players[targetId], target.alive else { return false }
        mafiaVotes[voterId] = targetId
        return isNightReady()
    }

    @discardableResult
    func submitDoctorTarget(doctorId: String, targetId: String) -> Bool {
        guard phase == .night,
              let doc = players[doctorId], doc.alive, doc.role == .doctor,
              let target = players[targetId], target.alive else { return false }
        if targetId == doctorId && doctorSelfSaveUsed { return false }
        doctorTarget = targetId
        return isNightReady()
    }

    private func isNightReady() -> Bool {
        let mafiaSubmitted = aliveMafia.allSatisfy { mafiaVotes[$0.id] != nil }
        let doctorSubmitted = aliveDoctors.isEmpty || doctorTarget != nil
        return mafiaSubmitted && doctorSubmitted
    }

    @discardableResult
    func resolveNight() -> NightOutcome {
        var tally: [String: Int] = [:]
        for t in mafiaVotes.values { tally[t, default: 0] += 1 }
        let killTarget = uniqueMax(tally)

        var saved: String?
        var finalKill = killTarget
        if let dt = doctorTarget, dt == killTarget {
            saved = dt
            if dt == aliveDoctors.first?.id { doctorSelfSaveUsed = true }
            finalKill = nil
        }
        if let k = finalKill { players[k]?.alive = false }

        let out = NightOutcome(killedId: finalKill, savedId: saved)
        lastNight = out
        mafiaVotes.removeAll()
        doctorTarget = nil
        phase = .dayReveal
        return out
    }

    func advanceToDayVote() {
        guard phase == .dayReveal else { return }
        dayVotes.removeAll()
        if checkWin() { return }
        phase = .dayVote
    }

    // MARK: Day
    @discardableResult
    func submitDayVote(voterId: String, targetId: String?) -> Bool {
        guard phase == .dayVote,
              let voter = players[voterId], voter.alive else { return false }
        if let t = targetId, let p = players[t], !p.alive { return false }
        if let t = targetId, players[t] == nil { return false }
        dayVotes[voterId] = targetId
        return alive.allSatisfy { dayVotes[$0.id] != nil }
    }

    @discardableResult
    func resolveDay() -> DayOutcome {
        var tally: [String: Int] = [:]
        for case let .some(t) in dayVotes.values { tally[t, default: 0] += 1 }
        let candidate = uniqueMax(tally)
        var eliminated: String?
        if let c = candidate, let maxCount = tally[c], maxCount * 2 > alive.count {
            eliminated = c
        }
        if let e = eliminated { players[e]?.alive = false }
        let out = DayOutcome(eliminatedId: eliminated, tally: tally)
        lastDay = out
        if checkWin() { return out }
        day += 1
        phase = .night
        return out
    }

    private func checkWin() -> Bool {
        let liveMafiaCount = aliveMafia.count
        let liveTownCount = alive.filter { $0.role != .mafia }.count
        if liveMafiaCount == 0 { winner = .town; phase = .gameOver; return true }
        if liveMafiaCount >= liveTownCount { winner = .mafia; phase = .gameOver; return true }
        return false
    }

    private func uniqueMax(_ tally: [String: Int]) -> String? {
        var maxCount = 0
        var tied: [String] = []
        for (id, c) in tally {
            if c > maxCount { maxCount = c; tied = [id] }
            else if c == maxCount { tied.append(id) }
        }
        return tied.count == 1 ? tied[0] : nil
    }
}
