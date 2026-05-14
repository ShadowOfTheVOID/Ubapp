import Foundation

/// Wraps [HostServer] with Mafia-specific routing. Owns the engine, fans out
/// the right private/public messages, and converts incoming guest commands
/// into engine calls. Mirrors lib/games/mafia/mafia_server.dart, minus the
/// in-app tutorial-vote handshake (TODO: port from TutorialVote).
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
        self.server = server ?? HostServer(html: MafiaBrowser.html)
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

    // MARK: Host-side actions
    func hostStart() {
        guard engine.canStart else { return }
        engine.start()
        broadcastPhase()
        sendRolesPrivately()
        emit()
    }
    func hostNightAction(targetId: String) { applyNightAction(playerId: Self.hostId, targetId: targetId) }
    func hostDayVote(targetId: String?) { applyDayVote(playerId: Self.hostId, targetId: targetId) }

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
        default: break
        }
    }

    private func onLeave(_ guest: GuestId) {
        guard let pid = guestToPlayer.removeValue(forKey: guest) else { return }
        playerToGuest[pid] = nil
        engine.removePlayer(pid)
        broadcastLobby()
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
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name])
        broadcastLobby()
        emit()
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
