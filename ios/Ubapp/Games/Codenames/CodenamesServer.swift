import Foundation

/// Wraps [HostServer] with Codenames-specific routing. Mirrors
/// lib/games/codenames/codenames_server.dart.
final class CodenamesServer {
    let engine = CodenamesEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "codenames_browser"))
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
    func makeLoopback() -> LoopbackGuest { LoopbackGuest(server: server) }
    func stop() { server.stop() }
    var guestCount: Int { server.guestCount }

    // MARK: Host-side actions
    func hostJoinTeam(_ team: Team) {
        engine.setTeam(Self.hostId, team)
        broadcastLobby(); sendRolesToAll(); emit()
    }
    func hostSetSpymaster(_ on: Bool) {
        engine.setSpymaster(Self.hostId, on)
        broadcastLobby(); sendRolesToAll(); emit()
    }
    func hostSetOptions(_ o: CodenamesOptions) {
        engine.setOptions(o)
        broadcastOptions(); emit()
    }
    func hostStart() {
        engine.start()
        broadcastState(); sendRolesToAll(); emit()
    }
    func hostSubmitClue(_ clue: String, number: Int) {
        engine.submitClue(spymasterId: Self.hostId, clue: clue, number: number)
        broadcastState(); emit()
    }
    func hostGuess(_ index: Int) {
        _ = engine.guess(guesserId: Self.hostId, boardIndex: index)
        broadcastState(); emit()
    }
    func hostEndTurn() {
        engine.endTurn(guesserId: Self.hostId)
        broadcastState(); emit()
    }
    func hostNewGame() {
        engine.reset()
        broadcast(["type": "reset"])
        broadcastLobby(); emit()
    }
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
        let pid = guestToPlayer[guest]
        switch type {
        case "join": handleJoin(guest, json: j)
        case "team":
            if let pid, let t = j["team"] as? String, let team = Team(rawValue: t) {
                engine.setTeam(pid, team); broadcastLobby(); sendRolesToAll(); emit()
            }
        case "spymaster":
            if let pid, let on = j["on"] as? Bool {
                engine.setSpymaster(pid, on); broadcastLobby(); sendRolesToAll(); emit()
            }
        case "clue":
            if let pid, let c = j["clue"] as? String, let n = j["number"] as? Int {
                engine.submitClue(spymasterId: pid, clue: c, number: n)
                broadcastState(); emit()
            }
        case "guess":
            if let pid, let idx = j["index"] as? Int {
                _ = engine.guess(guesserId: pid, boardIndex: idx)
                broadcastState(); emit()
            }
        case "end_turn":
            if let pid { engine.endTurn(guesserId: pid); broadcastState(); emit() }
        case "set_options":
            // Only the host may mutate options.
            break
        case "call_tutorial_vote": openTutorialVote()
        case "tutorial_vote":
            if let pid, let yes = j["yes"] as? Bool { submitTutorialVote(voterId: pid, yes: yes) }
        default: break
        }
    }

    private func onLeave(_ guest: GuestId) {
        guard let pid = guestToPlayer.removeValue(forKey: guest) else { return }
        playerToGuest[pid] = nil
        if engine.phase == .lobby {
            engine.removePlayer(pid)
            engine.tutorialVote.removeVoter(pid)
            broadcastLobby()
            if engine.tutorialVote.isOpen || engine.tutorialVote.hasResult {
                broadcastTutorialState()
            }
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
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "codenames"])
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private func broadcastOptions() {
        let o = engine.options
        broadcast([
            "type": "options",
            "boardSize": o.boardSize,
            "assassinCount": o.assassinCount,
            "allowedSizes": CodenamesOptions.allowedSizes,
        ])
    }

    // MARK: Outbound
    private func broadcastLobby() {
        broadcast([
            "type": "lobby",
            "players": engine.players.values.map { p in
                var d: [String: Any] = ["id": p.id, "name": p.name, "isHost": p.isHost,
                                         "isSpymaster": p.isSpymaster]
                d["team"] = p.team?.rawValue as Any? ?? NSNull()
                return d
            },
            "canStart": engine.canStart,
        ])
    }

    private func broadcastState() {
        let boardPublic: [[String: Any]] = engine.board.map { c in
            var d: [String: Any] = ["word": c.word, "revealed": c.revealed]
            if c.revealed { d["kind"] = c.kind.rawValue }
            return d
        }
        broadcast([
            "type": "state",
            "phase": engine.phase == .playing ? "playing" : "gameOver",
            "currentTeam": engine.currentTeam.rawValue,
            "currentClue": engine.currentClue as Any,
            "currentNumber": engine.currentNumber,
            "guessesLeft": engine.guessesLeftThisTurn,
            "redLeft": engine.cardsLeftFor(team: .red),
            "blueLeft": engine.cardsLeftFor(team: .blue),
            "board": boardPublic,
            "winner": engine.winner?.rawValue as Any,
            "endReason": engine.endReason as Any,
            "lastEvent": engine.lastEvent ?? "",
        ])
    }

    private func sendRolesToAll() {
        // Includes the host: it plays through its own in-process loopback
        // guest, so it must receive the same private role message.
        for p in engine.players.values {
            guard let guest = playerToGuest[p.id] else { continue }
            var payload: [String: Any] = [
                "type": "role",
                "team": p.team?.rawValue as Any,
                "isSpymaster": p.isSpymaster,
            ]
            if p.isSpymaster, !engine.board.isEmpty {
                payload["smView"] = engine.board.map { ["kind": $0.kind.rawValue] }
            }
            send(guest, payload)
        }
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
            payload["title"] = GameTutorials.codenames.title
            payload["sections"] = GameTutorials.codenames.sectionsJSON()
            payload["menuSections"] = GameTutorials.codenames.browserMenuSectionsJSON()
        }
        broadcast(payload)
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
