import Foundation

/// Wraps [HostServer] with Mafia-specific routing. Owns the engine, fans out
/// the right private/public messages, and converts incoming guest commands
/// into engine calls. Mirrors lib/games/mafia/mafia_server.dart, including
/// the tutorial-vote handshake.
final class MafiaServer {
    let engine = MafiaEngine()
    /// Flutter host plays as this player; not connected over WebSocket.
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "mafia_browser"))
        self.hostName = hostName
        self.server.onMessage = { [weak self] id, raw in self?.onMessage(from: id, raw: raw) }
        self.server.onLeave = { [weak self] id in self?.onLeave(id) }
    }

    @discardableResult
    func start() throws -> URL? {
        engine.addPlayer(id: Self.hostId, name: hostName, isHost: true)
        let url = try server.start()
        // The host plays as a normal player on the same screen guests see.
        // Bind its in-process pipe to the `host` engine player so private
        // sends (role) reach it and its inbound commands route as that player.
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
    func hostSetOptions(_ o: MafiaOptions) {
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

    func hostCallTutorialVote() { openTutorialVote() }
    func hostTutorialVote(_ yes: Bool) { submitTutorialVote(voterId: Self.hostId, yes: yes) }
    func hostDismissTutorial() {
        engine.tutorialVote.markShown()
        broadcastTutorialState(); emit()
    }

    func advanceFromReveal() {
        engine.advanceToDayVote()
        if engine.phase == .gameOver { broadcastGameOver() } else { broadcastPhase() }
        emit()
    }

    // MARK: Guest messages
    private func onMessage(from guest: GuestId, raw: String) {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return }
        switch type {
        case "join":
            handleJoin(guest, json: j)
        case "night_action":
            if let pid = guestToPlayer[guest], let t = j["targetId"] as? String {
                applyNightAction(playerId: pid, targetId: t)
            }
        case "vote":
            if let pid = guestToPlayer[guest] {
                applyDayVote(playerId: pid, targetId: j["targetId"] as? String)
            }
        case "set_options":
            // Only the host (which doesn't connect over WebSocket) may
            // mutate options. Ignore inbound from guests.
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
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "mafia"])
        broadcastLobby()
        broadcastOptions()
        broadcastTutorialState()
        emit()
    }

    private func broadcastOptions() {
        let o = engine.options
        broadcast([
            "type": "options",
            "mafiaCount": o.mafiaCount as Any,
            "doctorEnabled": o.doctorEnabled,
            "maxMafiaCount": engine.maxMafiaCount,
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
            payload["title"] = GameTutorials.mafia.title
            payload["sections"] = GameTutorials.mafia.sectionsJSON()
            payload["menuSections"] = GameTutorials.mafia.browserMenuSectionsJSON()
        }
        broadcast(payload)
    }

    private func applyNightAction(playerId: String, targetId: String) {
        guard let p = engine.players[playerId], p.alive else { return }
        var ready = false
        if p.role == .mafia {
            ready = engine.submitMafiaVote(voterId: playerId, targetId: targetId)
        } else if p.role == .doctor {
            ready = engine.submitDoctorTarget(doctorId: playerId, targetId: targetId)
        }
        emit()
        if ready { engine.resolveNight(); broadcastNightResult(); emit() }
    }

    private func applyDayVote(playerId: String, targetId: String?) {
        let ready = engine.submitDayVote(voterId: playerId, targetId: targetId)
        broadcastVoteUpdate()
        emit()
        if ready {
            engine.resolveDay()
            broadcastDayResult()
            if engine.phase == .gameOver { broadcastGameOver() } else { broadcastPhase() }
            emit()
        }
    }

    // MARK: Outbound
    private func broadcastLobby() {
        broadcast([
            "type": "lobby",
            "players": engine.players.values.map { ["id": $0.id, "name": $0.name, "isHost": $0.isHost] },
            "canStart": engine.canStart,
        ])
    }

    private func sendRolesPrivately() {
        let mafiaIds = engine.players.values.filter { $0.role == .mafia }.map(\.id)
        for p in engine.players.values {
            var payload: [String: Any] = ["type": "role", "role": p.role!.rawValue]
            if p.role == .mafia { payload["mafiaIds"] = mafiaIds }
            if let guest = playerToGuest[p.id] { send(guest, payload) }
        }
    }

    private func broadcastPhase() {
        broadcast([
            "type": "phase",
            "phase": String(describing: engine.phase),
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
            "phase": String(describing: engine.phase),
            "day": engine.day,
            "alive": engine.alive.map(publicPlayer),
            "dead": engine.dead.map(publicPlayer),
            "killedId": n.killedId as Any,
            "savedId": n.savedId as Any,
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

    private func broadcastGameOver() {
        var roles: [String: String] = [:]
        for p in engine.players.values { roles[p.id] = p.role!.rawValue }
        broadcast([
            "type": "game_over",
            "winner": engine.winner == .town ? "town" : "mafia",
            "roles": roles,
        ])
    }

    private func publicPlayer(_ p: MafiaPlayer) -> [String: Any] {
        ["id": p.id, "name": p.name, "alive": p.alive]
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
