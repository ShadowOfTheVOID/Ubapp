import Foundation

/// Wraps `HostServer` with The Bureaucrat's routing. Owns the engine, the
/// rebuttal countdown (the one piece of real I/O the pure engine refuses to
/// touch), and the `ContradictionDetector` that judges rebuttals. Mirrors
/// `BureaucratServer.kt` and the structure of `MafiaServer`.
final class BureaucratServer {
    private(set) var engine = BureaucratEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    /// NLI model when its assets are bundled, else the offline keyword check.
    private let detector: ContradictionDetector =
        OnnxContradictionDetector.tryCreate() ?? KeywordContradictionDetector()

    private var rebuttalWork: DispatchWorkItem?
    private var rebuttalDeadlineMs: Int64 = 0

    var onStateChange: (() -> Void)?
    private var statRecorded = false

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "bureaucrat_browser"))
        self.hostName = hostName
        self.server.onMessage = { [weak self] id, raw in self?.onMessage(from: id, raw: raw) }
        self.server.onLeave = { [weak self] id in self?.onLeave(id) }
    }

    @discardableResult
    func start() throws -> URL? {
        engine.addPlayer(id: Self.hostId, name: hostName, isHost: true)
        let url = try server.start()
        let local = server.attachLocalGuest()
        guestToPlayer[local] = Self.hostId
        playerToGuest[Self.hostId] = local
        emit()
        return url
    }

    @MainActor
    func makeLoopback() -> LoopbackGuest { LoopbackGuest(server: server) }

    func stop() { cancelTimer(); server.stop(); resetState() }

    /// Clear all per-session state so the next time the host starts
    /// hosting they get a fresh screen — empty lobby, tutorial vote
    /// available again.
    private func resetState() {
        engine = BureaucratEngine()
        guestToPlayer.removeAll(); playerToGuest.removeAll()
        rebuttalDeadlineMs = 0
        statRecorded = false
        emit()
    }
    var guestCount: Int { server.guestCount }

    // MARK: Host orchestration
    func hostSetOptions(_ o: BureaucratOptions) { engine.setOptions(o); broadcastOptions(); emit() }
    func hostStart() {
        guard engine.canStart else { return }
        engine.start(); broadcastRound(); emit()
    }
    func hostSurvive() {
        if engine.bureaucratSurvives() { cancelTimer(); broadcastRoundOver(); emit() }
    }
    func hostNextRound() {
        if engine.nextRound() {
            if engine.phase == .gameOver { broadcastGameOver() } else { broadcastRound() }
            emit()
        }
    }
    func hostCallTutorialVote() { openTutorialVote() }
    func hostTutorialVote(_ yes: Bool) { submitTutorialVote(voterId: Self.hostId, yes: yes) }
    func hostDismissTutorial() { engine.tutorialVote.markShown(); broadcastTutorialState(); emit() }

    // MARK: Inbound
    private func onMessage(from guest: GuestId, raw: String) {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return }
        let pid = guestToPlayer[guest]
        switch type {
        case "join": handleJoin(guest, json: j)
        case "denial":
            if let pid, let t = j["text"] as? String { applyDenial(playerId: pid, text: t) }
        case "call_loophole":
            if let pid { applyLoophole(citizenId: pid) }
        case "rebuttal":
            if let pid, let t = j["text"] as? String { applyRebuttal(playerId: pid, text: t) }
        case "call_tutorial_vote": openTutorialVote()
        case "tutorial_vote":
            if let pid, let yes = j["yes"] as? Bool { submitTutorialVote(voterId: pid, yes: yes) }
        default: break
        }
    }

    private func onLeave(_ guest: GuestId) {
        guard let pid = guestToPlayer.removeValue(forKey: guest) else { return }
        playerToGuest[pid] = nil
        engine.removePlayer(pid)
        engine.tutorialVote.removeVoter(pid)
        broadcastLobby()
        if engine.tutorialVote.isOpen || engine.tutorialVote.hasResult { broadcastTutorialState() }
        emit()
    }

    private func handleJoin(_ guest: GuestId, json: [String: Any]) {
        if engine.phase != .lobby {
            send(guest, ["type": "error", "message": "Game already started"]); return
        }
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return }
        let pid = "g\(guestToPlayer.count + 1)"
        engine.addPlayer(id: pid, name: name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "bureaucrat"])
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private func applyDenial(playerId: String, text: String) {
        if engine.addDenial(playerId: playerId, text: text) { broadcastPolicy(); emit() }
    }

    private func applyLoophole(citizenId: String) {
        if engine.callLoophole(citizenId: citizenId) {
            rebuttalDeadlineMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(engine.options.rebuttalSeconds) * 1000
            broadcastRebuttalOpen()
            startTimer()
            emit()
        }
    }

    private func applyRebuttal(playerId: String, text: String) {
        guard engine.phase == .rebuttal, playerId == engine.bureaucratId,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cancelTimer()
        let contradicts = engine.options.aiAssist
            && detector.contradicts(priorStatements: engine.policyLog.map { $0.text }, rebuttal: text)
        if engine.submitRebuttal(text: text, contradicts: contradicts) {
            if engine.phase == .roundOver { broadcastRoundOver() } else { broadcastPolicy() }
            emit()
        }
    }

    private func startTimer() {
        cancelTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.engine.rebuttalTimedOut() { self.broadcastRoundOver(); self.emit() }
        }
        rebuttalWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(engine.options.rebuttalSeconds), execute: work)
    }
    private func cancelTimer() { rebuttalWork?.cancel(); rebuttalWork = nil }

    // MARK: Outbound
    private func broadcastLobby() {
        broadcast([
            "type": "lobby",
            "players": engine.players.values.map { ["id": $0.id, "name": $0.name, "isHost": $0.isHost] },
            "canStart": engine.canStart,
        ])
    }

    private func broadcastOptions() {
        let o = engine.options
        broadcast(["type": "options", "targetScore": o.targetScore, "challengeTokens": o.challengeTokens,
                   "rebuttalSeconds": o.rebuttalSeconds, "aiAssist": o.aiAssist,
                   "rebuttalMode": o.rebuttalMode])
    }

    private func roundCore(_ type: String) -> [String: Any] {
        [
            "type": type,
            "phase": phaseJson(engine.phase),
            "roundNumber": engine.roundNumber,
            "bureaucratId": engine.bureaucratId as Any,
            "bureaucratName": engine.bureaucratId.flatMap { engine.players[$0]?.name } as Any,
            "task": engine.task as Any,
            "targetScore": engine.options.targetScore,
            "scores": scoresJson(),
            "tokens": tokensJson(),
            "policyLog": policyJson(),
        ]
    }
    private func broadcastRound() { broadcast(roundCore("round")) }
    private func broadcastPolicy() { broadcast(roundCore("policy")) }

    private func broadcastRebuttalOpen() {
        let cid = engine.pendingChallenger
        broadcast([
            "type": "rebuttal_open",
            "challengerId": cid as Any,
            "challengerName": cid.flatMap { engine.players[$0]?.name } as Any,
            "seconds": engine.options.rebuttalSeconds,
            "deadlineMs": rebuttalDeadlineMs,
            "policyLog": policyJson(),
        ])
    }

    private func broadcastRoundOver() {
        let r = engine.lastRound!
        broadcast([
            "type": "round_over",
            "bureaucratId": r.bureaucratId,
            "bureaucratName": engine.players[r.bureaucratId]?.name ?? r.bureaucratId,
            "challengerId": r.challengerId as Any,
            "challengerName": r.challengerId.flatMap { engine.players[$0]?.name } as Any,
            "reason": reasonJson(r.reason),
            "task": r.task,
            "nextBureaucratId": engine.nextBureaucratId() as Any,
            "scores": scoresJson(),
            "targetScore": engine.options.targetScore,
            "policyLog": policyJson(),
        ])
    }

    private func broadcastGameOver() {
        if !statRecorded {
            statRecorded = true
            StatsStore.record(gameId: "bureaucrat",
                              players: engine.players.values.map { $0.name },
                              outcome: engine.winnerId.flatMap { engine.players[$0]?.name } ?? "?")
        }
        broadcast([
            "type": "game_over",
            "winnerId": engine.winnerId as Any,
            "winnerName": engine.winnerId.flatMap { engine.players[$0]?.name } as Any,
            "scores": scoresJson(),
        ])
    }

    private func scoresJson() -> [String: Int] {
        var o: [String: Int] = [:]; for p in engine.players.values { o[p.id] = p.score }; return o
    }
    private func tokensJson() -> [String: Int] {
        var o: [String: Int] = [:]; for c in engine.citizens { o[c.id] = engine.tokensFor(c.id) }; return o
    }
    private func policyJson() -> [[String: Any]] {
        engine.policyLog.map { ["text": $0.text, "isRebuttal": $0.isRebuttal, "challengerId": $0.challengerId as Any] }
    }

    private func openTutorialVote() {
        guard engine.phase == .lobby, !engine.tutorialVote.isOpen, !engine.tutorialVote.tutorialShown else { return }
        engine.tutorialVote.open(eligibleIds: engine.players.keys)
        broadcastTutorialState(); emit()
    }
    private func submitTutorialVote(voterId: String, yes: Bool) {
        guard engine.tutorialVote.isOpen else { return }
        engine.tutorialVote.submit(voterId: voterId, yes: yes)
        broadcastTutorialState(); emit()
    }
    private func broadcastTutorialState() {
        let v = engine.tutorialVote
        var payload: [String: Any] = [
            "type": "tutorial_vote_state",
            "isOpen": v.isOpen, "yesCount": v.yesCount, "noCount": v.noCount,
            "eligibleCount": v.eligibleCount,
            "result": v.result.map { $0 as Any } ?? NSNull(),
            "tutorialShown": v.tutorialShown,
        ]
        if v.result == true && !v.tutorialShown {
            payload["title"] = GameTutorials.bureaucrat.title
            payload["sections"] = GameTutorials.bureaucrat.sectionsJSON()
            payload["menuSections"] = GameTutorials.bureaucrat.browserMenuSectionsJSON()
        }
        broadcast(payload)
    }

    private func phaseJson(_ p: BureaucratPhase) -> String {
        switch p {
        case .lobby: "lobby"; case .arguing: "arguing"; case .rebuttal: "rebuttal"
        case .roundOver: "roundOver"; case .gameOver: "gameOver"
        }
    }
    private func reasonJson(_ r: RoundEndReason) -> String {
        switch r {
        case .loopholeTimeout: "timeout"; case .loopholeContradiction: "contradiction"
        case .bureaucratSurvived: "survived"; case .tokensExhausted: "exhausted"
        }
    }

    private func emit() { onStateChange?() }
    private func broadcast(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else { return }
        server.broadcast(s)
    }
    private func send(_ guest: GuestId, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else { return }
        server.send(to: guest, s)
    }
}
