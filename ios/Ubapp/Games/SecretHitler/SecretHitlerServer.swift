import Foundation

/// Wraps `HostServer` with Secret-Hitler-specific routing. Owns the engine,
/// fans out per-phase public state plus per-player private state (presidential
/// hand, chancellor hand, peek result, investigation result), and converts
/// guest commands into engine calls.
final class SecretHitlerServer {
    let engine = SecretHitlerEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "secret_hitler_browser"))
        self.hostName = hostName
        self.server.onMessage = { [weak self] id, raw in self?.onMessage(from: id, raw: raw) }
        self.server.onLeave = { [weak self] id in self?.onLeave(id) }
    }

    @discardableResult
    func start() throws -> URL? {
        engine.addPlayer(id: Self.hostId, name: hostName, isHost: true)
        let url = try server.start()
        emit()
        return url
    }

    func stop() { server.stop() }
    var guestCount: Int { server.guestCount }

    // MARK: Host actions
    func hostStart() {
        guard engine.canStart else { return }
        engine.start()
        sendRoles()
        broadcastState()
        emit()
    }
    func hostNominate(_ targetId: String) { applyNominate(by: Self.hostId, targetId: targetId) }
    func hostVote(_ ja: Bool) { applyVote(voterId: Self.hostId, ja: ja) }
    func hostDiscard(index: Int) { applyDiscard(playerId: Self.hostId, index: index) }
    func hostEnact(index: Int) { applyEnact(playerId: Self.hostId, index: index) }
    func hostRequestVeto() { applyRequestVeto(playerId: Self.hostId) }
    func hostVetoResponse(_ confirm: Bool) { applyVetoResponse(playerId: Self.hostId, confirm: confirm) }
    func hostAcknowledgePeek() { applyAcknowledgePeek(playerId: Self.hostId) }
    func hostInvestigate(_ targetId: String) { applyInvestigate(playerId: Self.hostId, targetId: targetId) }
    func hostAcknowledgeInvestigation() { applyAcknowledgeInvestigation(playerId: Self.hostId) }
    func hostSpecialElection(_ targetId: String) { applySpecialElection(playerId: Self.hostId, targetId: targetId) }
    func hostExecute(_ targetId: String) { applyExecute(playerId: Self.hostId, targetId: targetId) }

    func hostCallTutorialVote() { openTutorialVote() }
    func hostTutorialVote(_ yes: Bool) { submitTutorialVote(voterId: Self.hostId, yes: yes) }
    func hostDismissTutorial() {
        engine.tutorialVote.markShown()
        broadcastTutorialState(); emit()
    }

    // MARK: Inbound
    private func onMessage(from guest: GuestId, raw: String) {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return }
        switch type {
        case "join": handleJoin(guest, json: j)
        case "nominate":
            if let pid = guestToPlayer[guest], let t = j["targetId"] as? String {
                applyNominate(by: pid, targetId: t)
            }
        case "vote":
            if let pid = guestToPlayer[guest], let ja = j["ja"] as? Bool {
                applyVote(voterId: pid, ja: ja)
            }
        case "discard":
            if let pid = guestToPlayer[guest], let i = j["index"] as? Int {
                applyDiscard(playerId: pid, index: i)
            }
        case "enact":
            if let pid = guestToPlayer[guest], let i = j["index"] as? Int {
                applyEnact(playerId: pid, index: i)
            }
        case "request_veto":
            if let pid = guestToPlayer[guest] { applyRequestVeto(playerId: pid) }
        case "veto_response":
            if let pid = guestToPlayer[guest], let c = j["confirm"] as? Bool {
                applyVetoResponse(playerId: pid, confirm: c)
            }
        case "ack_peek":
            if let pid = guestToPlayer[guest] { applyAcknowledgePeek(playerId: pid) }
        case "investigate":
            if let pid = guestToPlayer[guest], let t = j["targetId"] as? String {
                applyInvestigate(playerId: pid, targetId: t)
            }
        case "ack_investigation":
            if let pid = guestToPlayer[guest] { applyAcknowledgeInvestigation(playerId: pid) }
        case "special_election":
            if let pid = guestToPlayer[guest], let t = j["targetId"] as? String {
                applySpecialElection(playerId: pid, targetId: t)
            }
        case "execute":
            if let pid = guestToPlayer[guest], let t = j["targetId"] as? String {
                applyExecute(playerId: pid, targetId: t)
            }
        case "call_tutorial_vote": openTutorialVote()
        case "tutorial_vote":
            if let pid = guestToPlayer[guest], let yes = j["yes"] as? Bool {
                submitTutorialVote(voterId: pid, yes: yes)
            }
        default: break
        }
    }

    private func onLeave(_ guest: GuestId) {
        guard let pid = guestToPlayer.removeValue(forKey: guest) else { return }
        playerToGuest[pid] = nil
        engine.removePlayer(pid)
        engine.tutorialVote.removeVoter(pid)
        broadcastState()
        if engine.tutorialVote.isOpen || engine.tutorialVote.hasResult {
            broadcastTutorialState()
        }
        emit()
    }

    private func handleJoin(_ guest: GuestId, json: [String: Any]) {
        if engine.phase != .lobby {
            send(guest, ["type": "error", "message": "Game already started"])
            return
        }
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return }
        let pid = "g\(guestToPlayer.count + 1)"
        engine.addPlayer(id: pid, name: name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "secret_hitler"])
        broadcastState(); broadcastTutorialState(); emit()
    }

    // MARK: Action plumbing
    private func applyNominate(by playerId: String, targetId: String) {
        guard engine.phase == .nomination, playerId == engine.presidentId else { return }
        if engine.nominateChancellor(targetId) { broadcastState(); emit() }
    }
    private func applyVote(voterId: String, ja: Bool) {
        guard engine.phase == .election else { return }
        let ready = engine.submitVote(voterId: voterId, ja: ja)
        broadcastVoteProgress()
        emit()
        if ready {
            engine.resolveElection()
            broadcastElectionResult()
            if engine.phase == .gameOver { broadcastGameOver() }
            broadcastState()
            if engine.phase == .presidentDiscard { sendPresidentialHand() }
            emit()
        }
    }
    private func applyDiscard(playerId: String, index: Int) {
        guard engine.phase == .presidentDiscard, playerId == engine.presidentId else { return }
        if engine.presidentDiscard(index: index) {
            sendChancellorHand()
            broadcastState(); emit()
        }
    }
    private func applyEnact(playerId: String, index: Int) {
        guard engine.phase == .chancellorEnact, playerId == engine.chancellorId else { return }
        if engine.chancellorEnact(index: index) {
            broadcastPolicyResult()
            if engine.phase == .policyPeek { sendPolicyPeek() }
            if engine.phase == .investigationReveal { sendInvestigationResult() }
            if engine.phase == .gameOver { broadcastGameOver() }
            broadcastState(); emit()
        }
    }
    private func applyRequestVeto(playerId: String) {
        guard engine.phase == .chancellorEnact, playerId == engine.chancellorId else { return }
        if engine.chancellorRequestVeto() { broadcastState(); emit() }
    }
    private func applyVetoResponse(playerId: String, confirm: Bool) {
        guard engine.phase == .vetoDecision, playerId == engine.presidentId else { return }
        if engine.presidentVetoResponse(confirm: confirm) {
            if confirm { broadcastVetoResult() }
            broadcastState(); emit()
        }
    }
    private func applyAcknowledgePeek(playerId: String) {
        guard engine.phase == .policyPeek, playerId == engine.presidentId else { return }
        if engine.acknowledgePeek() { broadcastState(); emit() }
    }
    private func applyInvestigate(playerId: String, targetId: String) {
        guard engine.phase == .investigation, playerId == engine.presidentId else { return }
        if engine.investigate(targetId: targetId) {
            sendInvestigationResult()
            broadcastState(); emit()
        }
    }
    private func applyAcknowledgeInvestigation(playerId: String) {
        guard engine.phase == .investigationReveal, playerId == engine.presidentId else { return }
        if engine.acknowledgeInvestigation() { broadcastState(); emit() }
    }
    private func applySpecialElection(playerId: String, targetId: String) {
        guard engine.phase == .specialElection, playerId == engine.presidentId else { return }
        if engine.callSpecialElection(targetId: targetId) { broadcastState(); emit() }
    }
    private func applyExecute(playerId: String, targetId: String) {
        guard engine.phase == .execution, playerId == engine.presidentId else { return }
        if engine.executePlayer(targetId: targetId) {
            broadcastExecutionResult()
            if engine.phase == .gameOver { broadcastGameOver() }
            broadcastState(); emit()
        }
    }

    // MARK: Tutorial
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
            "eligibleCount": v.eligibleCount, "result": v.result as Any, "tutorialShown": v.tutorialShown,
        ]
        if v.result == true && !v.tutorialShown {
            payload["title"] = GameTutorials.secretHitler.title
            payload["sections"] = GameTutorials.secretHitler.sectionsJSON()
            payload["menuSections"] = GameTutorials.secretHitler.browserMenuSectionsJSON()
        }
        broadcast(payload)
    }

    // MARK: Outbound — public state
    private func publicPlayer(_ p: SecretHitlerPlayer) -> [String: Any] {
        ["id": p.id, "name": p.name, "alive": p.alive, "isHost": p.isHost]
    }

    private func broadcastState() {
        var payload: [String: Any] = [
            "type": "state",
            "phase": engine.phase.rawValue,
            "players": engine.seatOrder.compactMap { engine.players[$0] }.map(publicPlayer),
            "presidentId": engine.presidentId as Any,
            "chancellorNomineeId": engine.chancellorNomineeId as Any,
            "chancellorId": engine.chancellorId as Any,
            "liberalPolicies": engine.liberalPolicies,
            "fascistPolicies": engine.fascistPolicies,
            "electionTracker": engine.electionTracker,
            "vetoUnlocked": engine.vetoUnlocked,
            "vetoRequested": engine.vetoRequested,
            "drawPileCount": engine.drawPile.count,
            "discardPileCount": engine.discardPile.count,
            "canStart": engine.canStart,
            "eligibleChancellors": engine.phase == .nomination
                ? engine.eligibleChancellorNominees().map(\.id) : [],
            "voteProgress": engine.electionVotes.count,
            "voteTotal": engine.alive.count,
            "investigatedIds": Array(engine.investigatedIds),
        ]
        if let last = engine.lastEnactedPolicy {
            payload["lastEnactedPolicy"] = last.rawValue
            payload["lastEnactedByChaos"] = engine.lastEnactedByChaos
        }
        if let kid = engine.lastExecutedId { payload["lastExecutedId"] = kid }
        broadcast(payload)
    }

    private func broadcastVoteProgress() {
        broadcast([
            "type": "vote_progress",
            "voteProgress": engine.electionVotes.count,
            "voteTotal": engine.alive.count,
        ])
    }

    private func broadcastElectionResult() {
        guard let passed = engine.lastElectionPassed else { return }
        var voteMap: [String: Bool] = [:]
        for (k, v) in engine.electionVotes { voteMap[k] = v }
        broadcast([
            "type": "election_result",
            "passed": passed,
            "votes": voteMap,
            "electionTracker": engine.electionTracker,
        ])
    }

    private func broadcastPolicyResult() {
        guard let last = engine.lastEnactedPolicy else { return }
        broadcast([
            "type": "policy_enacted",
            "policy": last.rawValue,
            "liberalPolicies": engine.liberalPolicies,
            "fascistPolicies": engine.fascistPolicies,
            "byChaos": engine.lastEnactedByChaos,
        ])
    }

    private func broadcastVetoResult() {
        broadcast([
            "type": "veto_confirmed",
            "electionTracker": engine.electionTracker,
        ])
    }

    private func broadcastExecutionResult() {
        guard let kid = engine.lastExecutedId else { return }
        broadcast([
            "type": "executed",
            "playerId": kid,
        ])
    }

    private func broadcastGameOver() {
        var roles: [String: String] = [:]
        for p in engine.players.values { if let r = p.role { roles[p.id] = r.rawValue } }
        broadcast([
            "type": "game_over",
            "winner": engine.winner?.rawValue ?? "",
            "reason": engine.winReason?.rawValue ?? "",
            "roles": roles,
        ])
    }

    // MARK: Outbound — private overlays
    private func sendRoles() {
        for p in engine.players.values {
            guard let role = p.role else { continue }
            let allies = engine.knownAllies(for: p.id).compactMap { engine.players[$0] }.map {
                ["id": $0.id, "name": $0.name, "role": $0.role?.rawValue ?? ""]
            }
            let payload: [String: Any] = [
                "type": "role",
                "role": role.rawValue,
                "allies": allies,
            ]
            if let g = playerToGuest[p.id] { send(g, payload) }
        }
    }

    private func sendPresidentialHand() {
        guard let pid = engine.presidentId,
              let g = playerToGuest[pid] else { return }
        send(g, [
            "type": "presidential_hand",
            "policies": engine.presidentialHand.map { $0.rawValue },
        ])
    }

    private func sendChancellorHand() {
        guard let cid = engine.chancellorId,
              let g = playerToGuest[cid] else { return }
        send(g, [
            "type": "chancellor_hand",
            "policies": engine.chancellorHand.map { $0.rawValue },
            "vetoUnlocked": engine.vetoUnlocked,
        ])
    }

    private func sendPolicyPeek() {
        guard let pid = engine.presidentId,
              let g = playerToGuest[pid] else { return }
        send(g, [
            "type": "policy_peek",
            "policies": engine.peekedPolicies.map { $0.rawValue },
        ])
    }

    private func sendInvestigationResult() {
        guard let pid = engine.presidentId,
              let g = playerToGuest[pid],
              let inv = engine.lastInvestigation else { return }
        send(g, [
            "type": "investigation_result",
            "subjectId": inv.subjectId,
            "party": inv.party.rawValue,
        ])
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
