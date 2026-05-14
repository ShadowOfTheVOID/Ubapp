import Foundation

/// Wraps [HostServer] with Imposter-specific routing. Mirrors
/// lib/games/imposter/imposter_server.dart.
final class ImposterServer {
    let engine = ImposterEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "imposter_browser"))
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
    func hostStart(category: String? = nil) {
        engine.start(categoryName: category)
        sendRolesPrivately()
        emit()
    }
    func hostBeginVoting() {
        engine.beginVoting()
        broadcast(["type": "voting"])
        emit()
    }
    func hostVote(targetId: String?) { applyVote(voterId: Self.hostId, targetId: targetId) }
    func hostNewRound() {
        engine.reset()
        broadcast(["type": "reset"])
        broadcastLobby()
        emit()
    }
    func hostCallTutorialVote() { openTutorialVote() }
    func hostTutorialVote(_ yes: Bool) { submitTutorialVote(voterId: Self.hostId, yes: yes) }
    func hostDismissTutorial() {
        engine.tutorialVote.markShown()
        broadcastTutorialState()
        emit()
    }

    // MARK: Inbound
    private func onMessage(from guest: GuestId, raw: String) {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return }
        switch type {
        case "join": handleJoin(guest, json: j)
        case "vote":
            if let pid = guestToPlayer[guest] {
                applyVote(voterId: pid, targetId: j["targetId"] as? String)
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
        broadcastLobby()
        if engine.tutorialVote.isOpen || engine.tutorialVote.hasResult {
            broadcastTutorialState()
        }
        emit()
    }

    private func handleJoin(_ guest: GuestId, json: [String: Any]) {
        if engine.phase != .lobby {
            send(guest, ["type": "error", "message": "Game already in progress"])
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
        broadcastTutorialState()
        emit()
    }

    private func applyVote(voterId: String, targetId: String?) {
        let ready = engine.submitVote(voterId: voterId, targetId: targetId)
        emit()
        if ready { engine.resolveVotes(); broadcastResult(); emit() }
    }

    private func broadcastLobby() {
        broadcast([
            "type": "lobby",
            "players": engine.players.values.map { ["id": $0.id, "name": $0.name, "isHost": $0.isHost] },
            "canStart": engine.canStart,
        ])
    }

    private func sendRolesPrivately() {
        for p in engine.players.values where p.id != Self.hostId {
            var payload: [String: Any] = [
                "type": "role", "category": engine.category, "isImposter": p.isImposter,
            ]
            if !p.isImposter { payload["word"] = engine.secretWord }
            if let guest = playerToGuest[p.id] { send(guest, payload) }
        }
    }

    // MARK: Tutorial vote
    private func openTutorialVote() {
        guard engine.phase == .lobby, !engine.tutorialVote.isOpen, !engine.tutorialVote.tutorialShown else { return }
        engine.tutorialVote.open(eligibleIds: engine.players.keys)
        broadcastTutorialState()
        emit()
    }
    private func submitTutorialVote(voterId: String, yes: Bool) {
        guard engine.tutorialVote.isOpen else { return }
        engine.tutorialVote.submit(voterId: voterId, yes: yes)
        broadcastTutorialState()
        emit()
    }
    private func broadcastTutorialState() {
        let v = engine.tutorialVote
        var payload: [String: Any] = [
            "type": "tutorial_vote_state",
            "isOpen": v.isOpen, "yesCount": v.yesCount, "noCount": v.noCount,
            "eligibleCount": v.eligibleCount,
            "result": v.result as Any, "tutorialShown": v.tutorialShown,
        ]
        if v.result == true && !v.tutorialShown {
            payload["title"] = GameTutorials.imposter.title
            payload["sections"] = GameTutorials.imposter.sectionsJSON()
            payload["menuSections"] = GameTutorials.imposter.browserMenuSectionsJSON()
        }
        broadcast(payload)
    }

    private func broadcastResult() {
        broadcast([
            "type": "result",
            "winner": engine.winner == .town ? "town" : "imposter",
            "imposterId": engine.imposterId as Any,
            "mostVotedId": engine.mostVotedId as Any,
            "imposterCaught": engine.imposterCaught as Any,
            "word": engine.secretWord,
            "category": engine.category,
            "players": engine.players.values.map {
                ["id": $0.id, "name": $0.name, "isImposter": $0.isImposter]
            },
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
