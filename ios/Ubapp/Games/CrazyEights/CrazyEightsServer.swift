     import Foundation

/// Wraps [HostServer] with Crazy Eights routing. Mirrors
/// lib/games/crazy_eights/crazy_eights_server.dart.
final class CrazyEightsServer {
    let engine = CrazyEightsEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?
    private var statRecorded = false

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "crazy_eights_browser"))
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

    // MARK: Host actions
    func hostSetOptions(_ o: CrazyEightsOptions) {
        engine.setOptions(o)
        broadcastOptions(); emit()
    }
    func hostStart() {
        engine.start()
        broadcastState(); sendHandsPrivately(); emit()
    }
    @discardableResult
    func hostPlay(_ card: Card, declaredSuit: Suit? = nil) -> String? {
        let err = engine.playCard(playerId: Self.hostId, card: card, declaredSuit: declaredSuit)
        if err == nil {
            broadcastState(); sendHandsPrivately()
            if engine.phase == .gameOver { broadcastOver() }
            emit()
        }
        return err
    }
    func hostDraw() {
        _ = engine.drawOne(playerId: Self.hostId)
        broadcastState(); sendHandsPrivately(); emit()
    }
    func hostPass() {
        engine.passAfterDraw(playerId: Self.hostId)
        broadcastState(); emit()
    }
    func hostNewGame() {
        engine.reset()
        statRecorded = false
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
        switch type {
        case "join": handleJoin(guest, json: j)
        case "play":
            if let pid = guestToPlayer[guest] { applyPlay(pid, json: j) }
        case "draw":
            if let pid = guestToPlayer[guest] { applyDraw(pid) }
        case "pass":
            if let pid = guestToPlayer[guest] { applyPass(pid) }
        case "set_options":
            // Only the host may mutate options.
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
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "crazy_eights"])
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private func broadcastOptions() {
        let o = engine.options
        broadcast([
            "type": "options",
            "startingHandSize": o.startingHandSize as Any,
            "jackSkips": o.jackSkips,
            "queenReverses": o.queenReverses,
        ])
    }

    private func applyPlay(_ pid: String, json: [String: Any]) {
        guard let s = json["suit"] as? String, let suit = Suit(rawValue: s),
              let rank = json["rank"] as? Int else { return }
        let declared = (json["declaredSuit"] as? String).flatMap { Suit(rawValue: $0) }
        let err = engine.playCard(playerId: pid, card: Card(suit: suit, rank: rank), declaredSuit: declared)
        if err == nil {
            broadcastState(); sendHandsPrivately()
            if engine.phase == .gameOver { broadcastOver() }
            emit()
        } else if let guest = playerToGuest[pid] {
            send(guest, ["type": "error", "message": err!])
        }
    }
    private func applyDraw(_ pid: String) {
        _ = engine.drawOne(playerId: pid)
        broadcastState(); sendHandsPrivately(); emit()
    }
    private func applyPass(_ pid: String) {
        engine.passAfterDraw(playerId: pid)
        broadcastState(); emit()
    }

    // MARK: Outbound
    private func broadcastLobby() {
        broadcast([
            "type": "lobby",
            "players": engine.players.values.map { ["id": $0.id, "name": $0.name, "isHost": $0.isHost] },
        ])
    }
    private func broadcastState() {
        let phase: String
        switch engine.phase {
        case .lobby: phase = "lobby"
        case .playing: phase = "playing"
        case .gameOver: phase = "gameOver"
        }
        broadcast([
            "type": "state",
            "phase": phase,
            "currentId": engine.current?.id as Any,
            "topCard": engine.topCard.map { ["suit": $0.suit.rawValue, "rank": $0.rank] } as Any,
            "activeSuit": engine.activeSuit?.rawValue as Any,
            "drawCount": engine.drawPile.count,
            "justDrew": engine.justDrew,
            "lastEvent": engine.lastEvent ?? "",
            "players": engine.players.values.map {
                ["id": $0.id, "name": $0.name, "handCount": $0.hand.count]
            },
        ])
    }
    private func sendHandsPrivately() {
        // Includes the host: it plays through its own in-process loopback
        // guest, so it must receive its private hand.
        for p in engine.players.values {
            guard let guest = playerToGuest[p.id] else { continue }
            send(guest, [
                "type": "hand",
                "cards": p.hand.map { ["suit": $0.suit.rawValue, "rank": $0.rank] },
            ])
        }
    }
    private func broadcastOver() {
        if !statRecorded {
            statRecorded = true
            var names: [String] = []
            if let wid = engine.winnerId, let w = engine.players[wid] { names.append(w.name) }
            for p in engine.players.values where p.id != engine.winnerId { names.append(p.name) }
            StatsStore.record(gameId: "crazy_eights", players: names, outcome: "win")
        }
        broadcast([
            "type": "over",
            "winnerId": engine.winnerId as Any,
            "players": engine.players.values.map {
                ["id": $0.id, "name": $0.name, "handCount": $0.hand.count]
            },
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
            payload["title"] = GameTutorials.crazyEights.title
            payload["sections"] = GameTutorials.crazyEights.sectionsJSON()
            payload["menuSections"] = GameTutorials.crazyEights.browserMenuSectionsJSON()
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
