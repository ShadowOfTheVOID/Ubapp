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
    /// The detector's last ruling, surfaced to every client so the AI verdict
    /// is legible instead of opaque. Nil when no rebuttal has been judged this
    /// challenge (e.g. timeout) or AI assist is off.
    private var lastVerdict: [String: Any]?

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
        lastVerdict = nil
        engine.start(); broadcastRound(); emit()
    }
    func hostSurvive() {
        lastVerdict = nil
        if engine.bureaucratSurvives() { cancelTimer(); broadcastRoundOver(); emit() }
    }
    func hostNextRound() {
        lastVerdict = nil
        if engine.nextRound() {
            if engine.phase == .gameOver { broadcastGameOver() } else { broadcastRound() }
            emit()
        }
    }
    func hostCastVote(_ stands: Bool) { applyVote(voterId: Self.hostId, stands: stands) }
    func hostForceTally() {
        if engine.forceTally() { afterVoteResolved(); emit() }
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
            if let pid, let t = j["text"] as? String { applyDenial(playerId: pid, text: String(t.prefix(280))) }
        case "call_loophole":
            if let pid, let c = j["claim"] as? String { applyLoophole(citizenId: pid, claim: String(c.prefix(280))) }
        case "rebuttal":
            if let pid, let t = j["text"] as? String { applyRebuttal(playerId: pid, text: String(t.prefix(280))) }
        case "cast_vote":
            if let pid, let stands = j["stands"] as? Bool { applyVote(voterId: pid, stands: stands) }
        case "call_tutorial_vote": if pid != nil { openTutorialVote() }
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
        let name = String(((json["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces).prefix(24))
        guard !name.isEmpty else { return }
        let pid = "p\(guest.value)"
        engine.addPlayer(id: pid, name: name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "bureaucrat"])
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private func applyDenial(playerId: String, text: String) {
        if engine.addDenial(playerId: playerId, text: text) { broadcastPolicy(); emit() }
    }

    private func applyLoophole(citizenId: String, claim: String) {
        lastVerdict = nil
        if engine.callLoophole(citizenId: citizenId, claim: claim) {
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
        let voteMode = engine.options.judging == "vote"
        var contradicts = false
        if !voteMode && engine.options.aiAssist {
            // Judge the rebuttal only against the denials and the challenger's
            // claim — never the request, which a denial trivially contradicts.
            let judged = engine.policyLog.enumerated().filter { $0.element.kind != .request }
            let v = detector.judge(priorStatements: judged.map { $0.element.text }, rebuttal: text)
            contradicts = v.contradicts
            let lineIndex = (v.priorIndex >= 0 && v.priorIndex < judged.count) ? judged[v.priorIndex].offset : -1
            lastVerdict = [
                "contradicts": v.contradicts, "label": v.label,
                "confidence": v.confidence, "lineIndex": lineIndex, "rebuttal": text,
            ]
        }
        if engine.submitRebuttal(text: text, contradicts: contradicts) {
            switch engine.phase {
            case .voting: broadcastVoteState()      // table decides
            case .roundOver: broadcastRoundOver()
            default: broadcastPolicy()              // successful defence
            }
            emit()
        }
    }

    private func applyVote(voterId: String, stands: Bool) {
        guard engine.phase == .voting else { return }
        if engine.castVote(voterId: voterId, stands: stands) { afterVoteResolved(); emit() }
    }

    /// Re-broadcast whatever the vote produced: a running tally, the round-over
    /// screen (loophole carried) or back to arguing (denial upheld).
    private func afterVoteResolved() {
        switch engine.phase {
        case .voting: broadcastVoteState()
        case .roundOver: broadcastRoundOver()
        default: broadcastPolicy()
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
                   "rebuttalMode": o.rebuttalMode, "judging": o.judging])
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
    private func broadcastPolicy() {
        var core = roundCore("policy")
        if let v = lastVerdict { core["verdict"] = v }
        broadcast(core)
    }

    private func broadcastRebuttalOpen() {
        let cid = engine.pendingChallenger
        broadcast([
            "type": "rebuttal_open",
            "challengerId": cid as Any,
            "challengerName": cid.flatMap { engine.players[$0]?.name } as Any,
            "seconds": engine.options.rebuttalSeconds,
            "deadlineMs": rebuttalDeadlineMs,
            "claim": engine.policyLog.last(where: { $0.kind == .claim })?.text as Any,
            "policyLog": policyJson(),
        ])
    }

    /// Table-vote state: the open challenge plus the running tally. Sent on
    /// entering `.voting` and after every ballot.
    private func broadcastVoteState() {
        let cid = engine.pendingChallenger
        let stands = engine.votes.values.filter { $0 }.count
        broadcast([
            "type": "vote_state",
            "challengerId": cid as Any,
            "challengerName": cid.flatMap { engine.players[$0]?.name } as Any,
            "bureaucratId": engine.bureaucratId as Any,
            "claim": engine.policyLog.last(where: { $0.kind == .claim })?.text as Any,
            "rebuttal": engine.policyLog.last(where: { $0.kind == .rebuttal })?.text as Any,
            "standsCount": stands,
            "denialCount": engine.votes.count - stands,
            "eligibleCount": engine.voters.count,
            "policyLog": policyJson(),
        ])
    }

    private func broadcastRoundOver() {
        let r = engine.lastRound!
        var payload: [String: Any] = [
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
        ]
        if let v = lastVerdict { payload["verdict"] = v }
        broadcast(payload)
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
        engine.policyLog.map { ["text": $0.text, "kind": $0.kind.rawValue, "author": $0.authorId as Any] }
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
        case .voting: "voting"; case .roundOver: "roundOver"; case .gameOver: "gameOver"
        }
    }
    private func reasonJson(_ r: RoundEndReason) -> String {
        switch r {
        case .loopholeTimeout: "timeout"; case .loopholeContradiction: "contradiction"
        case .loopholeVote: "vote"
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
