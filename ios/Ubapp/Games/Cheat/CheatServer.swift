import Foundation

/// Wraps [HostServer] with Cheat (BS) routing. Mirrors the Crazy Eights
/// adapter — host is player id `host`, driven through an in-process
/// loopback so it plays on the same `CheatGuestView` every guest sees.
final class CheatServer {
    let engine = CheatEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?
    private var statRecorded = false
    private let series = SeriesScore()

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "cheat_browser"))
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
    func stop() { server.stop() }
    var guestCount: Int { server.guestCount }

    // MARK: Host actions
    func hostSetOptions(_ o: CheatOptions) {
        engine.setOptions(o)
        broadcastOptions(); emit()
    }
    func hostStart() {
        engine.start()
        broadcastState(); sendHandsPrivately(); emit()
    }
    func hostNewGame() {
        engine.reset()
        statRecorded = false
        broadcast(["type": "reset"])
        broadcastLobby(); broadcastTutorialState()
        if !series.isEmpty { broadcastSeries() }
        emit()
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
        case "bs":
            if let pid = guestToPlayer[guest] { applyBs(pid) }
        case "accept_win":
            if let pid = guestToPlayer[guest] { applyAccept(pid) }
        case "set_options":
            break // host-only
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
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "cheat"])
        broadcastLobby(); broadcastOptions(); broadcastTutorialState()
        if !series.isEmpty { broadcastSeries() }
        emit()
    }

    private func applyPlay(_ pid: String, json: [String: Any]) {
        guard let rank = json["claimedRank"] as? Int,
              let cardArr = json["cards"] as? [[String: Any]] else { return }
        var cards: [CheatCard] = []
        for c in cardArr {
            guard let s = c["suit"] as? String, let suit = CheatSuit(rawValue: s),
                  let r = c["rank"] as? Int else { return }
            cards.append(CheatCard(suit: suit, rank: r))
        }
        let err = engine.play(playerId: pid, cards: cards, claimedRank: rank)
        if err == nil {
            broadcastState(); sendHandsPrivately()
            if engine.phase == .gameOver { broadcastOver() }
            emit()
        } else if let g = playerToGuest[pid] {
            send(g, ["type": "error", "message": err!])
        }
    }

    private func applyBs(_ pid: String) {
        let err = engine.callBs(callerId: pid)
        if err == nil {
            broadcastState(); sendHandsPrivately()
            if engine.phase == .gameOver { broadcastOver() }
            emit()
        } else if let g = playerToGuest[pid] {
            send(g, ["type": "error", "message": err!])
        }
    }

    private func applyAccept(_ pid: String) {
        let err = engine.acceptWin(playerId: pid)
        if err == nil {
            broadcastState()
            if engine.phase == .gameOver { broadcastOver() }
            emit()
        } else if let g = playerToGuest[pid] {
            send(g, ["type": "error", "message": err!])
        }
    }

    // MARK: Outbound

    private func broadcastOptions() {
        broadcast([
            "type": "options",
            "freeClaim": engine.options.freeClaim,
            "randomStartRank": engine.options.randomStartRank,
            "descending": engine.options.descending,
        ])
    }

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
        case .pendingWin: phase = "pendingWin"
        case .gameOver: phase = "gameOver"
        }
        var payload: [String: Any] = [
            "type": "state",
            "phase": phase,
            "currentId": engine.current?.id as Any,
            "expectedRank": engine.expectedRank,
            "pileSize": engine.pile.count,
            "lastEvent": engine.lastEvent ?? "",
            "winnerId": engine.winnerId as Any,
            "players": engine.players.values.map {
                ["id": $0.id, "name": $0.name, "handCount": $0.hand.count]
            },
        ]
        if let lp = engine.lastPlay {
            payload["lastPlay"] = [
                "playerId": lp.playerId,
                "claimedRank": lp.claimedRank,
                "count": lp.count,
            ]
        }
        if let r = engine.lastReveal {
            payload["lastReveal"] = [
                "callerId": r.callerId,
                "accusedId": r.accusedId,
                "claimedRank": r.claimedRank,
                "truthful": r.truthful,
                "loserId": r.loserId,
                "cards": r.cards.map { ["suit": $0.suit.rawValue, "rank": $0.rank] },
            ]
        }
        broadcast(payload)
    }

    private func sendHandsPrivately() {
        for p in engine.players.values {
            guard let g = playerToGuest[p.id] else { continue }
            send(g, [
                "type": "hand",
                "cards": p.hand.map { ["suit": $0.suit.rawValue, "rank": $0.rank] },
            ])
        }
    }

    private func broadcastOver() {
        if !statRecorded {
            statRecorded = true
            let winnerName = engine.winnerId.flatMap { engine.players[$0]?.name }
            var names: [String] = []
            if let w = winnerName { names.append(w) }
            for p in engine.players.values where p.id != engine.winnerId { names.append(p.name) }
            StatsStore.record(gameId: "cheat", players: names, outcome: "win")
            if let w = winnerName { series.record(w); broadcastSeries() }
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
            payload["title"] = GameTutorials.cheat.title
            payload["sections"] = GameTutorials.cheat.sectionsJSON()
            payload["menuSections"] = GameTutorials.cheat.browserMenuSectionsJSON()
        }
        broadcast(payload)
    }

    private func broadcastSeries() {
        var scores: [String: Int] = [:]
        for entry in series.scores { scores[entry.key] = entry.value }
        broadcast(["type": "series_state", "rounds": series.rounds, "scores": scores])
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
