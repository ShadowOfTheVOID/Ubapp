import Foundation

/// Wraps [HostServer] with Werewolf-specific routing. Mirrors
/// lib/games/werewolf/werewolf_server.dart.
final class WerewolfServer {
    let engine = WerewolfEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "werewolf_browser"))
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

    /// In-process pipe for the host's own player view.
    @MainActor
    func makeLoopback() -> LoopbackGuest { LoopbackGuest(server: server) }
    func stop() { server.stop() }
    var guestCount: Int { server.guestCount }

    // MARK: Host-side actions
    func hostSetOptions(_ o: WerewolfOptions) {
        engine.setOptions(o)
        broadcastOptions(); emit()
    }
    func hostStart() {
        guard engine.canStart else { return }
        engine.start()
        broadcastPhase()
        sendRolesPrivately()
        emit()
    }
    func hostNightAction(targetId: String) { applyNightAction(playerId: Self.hostId, targetId: targetId) }
    func hostDayVote(targetId: String?) { applyDayVote(playerId: Self.hostId, targetId: targetId) }
    func hostHunterShot(targetId: String) { applyHunterShot(playerId: Self.hostId, targetId: targetId) }
    func hostCallTutorialVote() { openTutorialVote() }
    func hostTutorialVote(_ yes: Bool) { submitTutorialVote(voterId: Self.hostId, yes: yes) }
    func hostDismissTutorial() {
        engine.tutorialVote.markShown()
        broadcastTutorialState()
        emit()
    }
    func advanceFromReveal() {
        engine.advanceToDayVote()
        if engine.phase == .gameOver { broadcastGameOver() } else { broadcastPhase() }
        emit()
    }

    // MARK: Inbound
    private func onMessage(from guest: GuestId, raw: String) {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return }
        switch type {
        case "join": handleJoin(guest, json: j)
        case "night_action":
            if let pid = guestToPlayer[guest], let t = j["targetId"] as? String {
                applyNightAction(playerId: pid, targetId: t)
            }
        case "vote":
            if let pid = guestToPlayer[guest] {
                applyDayVote(playerId: pid, targetId: j["targetId"] as? String)
            }
        case "hunter_shot":
            if let pid = guestToPlayer[guest], let t = j["targetId"] as? String {
                applyHunterShot(playerId: pid, targetId: t)
            }
        case "set_options":
            // Only the host (not over WebSocket) may mutate options.
            break
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
        broadcastLobby()
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
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "werewolf"])
        broadcastLobby()
        broadcastOptions()
        broadcastTutorialState()
        emit()
    }

    private func broadcastOptions() {
        let o = engine.options
        broadcast([
            "type": "options",
            "wolfCount": o.wolfCount as Any,
            "seerEnabled": o.seerEnabled,
            "hunterEnabled": o.hunterEnabled,
            "maxWolfCount": engine.maxWolfCount,
        ])
    }

    private func applyNightAction(playerId: String, targetId: String) {
        guard let p = engine.players[playerId], p.alive else { return }
        var ready = false
        if p.role == .werewolf {
            ready = engine.submitWolfVote(voterId: playerId, targetId: targetId)
        } else if p.role == .seer {
            ready = engine.submitSeerTarget(seerId: playerId, targetId: targetId)
        }
        emit()
        if ready {
            engine.resolveNight()
            sendSeerResultPrivately()
            broadcastNightResult()
            if engine.phase == .gameOver { broadcastGameOver() }
            else if engine.phase == .hunterShot { broadcastHunterPrompt() }
            emit()
        }
    }

    private func applyDayVote(playerId: String, targetId: String?) {
        let ready = engine.submitDayVote(voterId: playerId, targetId: targetId)
        broadcastVoteUpdate()
        emit()
        if ready {
            engine.resolveDay()
            broadcastDayResult()
            if engine.phase == .gameOver { broadcastGameOver() }
            else if engine.phase == .hunterShot { broadcastHunterPrompt() }
            else { broadcastPhase() }
            emit()
        }
    }

    private func applyHunterShot(playerId: String, targetId: String) {
        let ok = engine.submitHunterShot(hunterId: playerId, targetId: targetId)
        if !ok { return }
        broadcastHunterShotResult()
        if engine.phase == .gameOver { broadcastGameOver() }
        else if engine.phase == .hunterShot { broadcastHunterPrompt() }
        else { broadcastPhase() }
        emit()
    }

    // MARK: Outbound
    private func broadcastLobby() {
        broadcast([
            "type": "lobby",
            "players": engine.players.values.map { ["id": $0.id, "name": $0.name, "isHost": $0.isHost] },
            "canStart": engine.canStart,
        ])
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
            "eligibleCount": v.eligibleCount, "result": v.result as Any, "tutorialShown": v.tutorialShown,
        ]
        if v.result == true && !v.tutorialShown {
            payload["title"] = GameTutorials.werewolf.title
            payload["sections"] = GameTutorials.werewolf.sectionsJSON()
            payload["menuSections"] = GameTutorials.werewolf.browserMenuSectionsJSON()
        }
        broadcast(payload)
    }

    private func sendRolesPrivately() {
        let wolfIds = engine.players.values.filter { $0.role == .werewolf }.map(\.id)
        for p in engine.players.values {
            var payload: [String: Any] = ["type": "role", "role": p.role!.rawValue]
            if p.role == .werewolf { payload["wolfIds"] = wolfIds }
            if let guest = playerToGuest[p.id] { send(guest, payload) }
        }
    }

    private func sendSeerResultPrivately() {
        guard let r = engine.lastSeerResult, let guest = playerToGuest[r.seerId] else { return }
        send(guest, ["type": "seer_result", "targetId": r.targetId, "isWerewolf": r.isWerewolf])
    }

    private func broadcastPhase() {
        broadcast([
            "type": "phase",
            "phase": phaseName(engine.phase),
            "day": engine.day,
            "alive": engine.alive.map(publicPlayer),
            "dead": engine.dead.map(publicPlayer),
        ])
    }
    private func broadcastVoteUpdate() {
        var votes: [String: String] = [:]
        for (k, v) in engine.dayVotes { votes[k] = v ?? "" }
        broadcast(["type": "vote_update", "votes": votes])
    }
    private func broadcastNightResult() {
        let n = engine.lastNight!
        broadcast([
            "type": "phase",
            "phase": phaseName(engine.phase),
            "day": engine.day,
            "alive": engine.alive.map(publicPlayer),
            "dead": engine.dead.map(publicPlayer),
            "killedId": n.killedId as Any,
        ])
    }
    private func broadcastDayResult() {
        let d = engine.lastDay!
        let role: Any = d.eliminatedId.flatMap { engine.players[$0]?.role?.rawValue } ?? NSNull()
        broadcast([
            "type": "day_result",
            "eliminatedId": d.eliminatedId as Any,
            "tally": d.tally,
            "alive": engine.alive.map(publicPlayer),
            "dead": engine.dead.map(publicPlayer),
            "eliminatedRole": role,
        ])
    }
    private func broadcastHunterPrompt() {
        broadcast([
            "type": "hunter_prompt",
            "hunterId": engine.pendingHunterShooter as Any,
            "alive": engine.alive.map(publicPlayer),
            "dead": engine.dead.map(publicPlayer),
        ])
    }
    private func broadcastHunterShotResult() {
        guard let last = engine.hunterShotsThisRound.last else { return }
        broadcast([
            "type": "hunter_shot_result",
            "hunterId": last.hunterId,
            "targetId": last.targetId,
            "targetRole": engine.players[last.targetId]!.role!.rawValue,
            "alive": engine.alive.map(publicPlayer),
            "dead": engine.dead.map(publicPlayer),
        ])
    }
    private func broadcastGameOver() {
        var roles: [String: String] = [:]
        for p in engine.players.values { roles[p.id] = p.role!.rawValue }
        broadcast([
            "type": "game_over",
            "winner": engine.winner == .town ? "town" : "werewolves",
            "roles": roles,
        ])
    }

    private func publicPlayer(_ p: WerewolfPlayer) -> [String: Any] {
        ["id": p.id, "name": p.name, "alive": p.alive]
    }

    private func phaseName(_ p: WerewolfPhase) -> String {
        switch p {
        case .lobby: "lobby"; case .night: "night"
        case .dayReveal: "dayReveal"; case .dayVote: "dayVote"
        case .hunterShot: "hunterShot"; case .gameOver: "gameOver"
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
