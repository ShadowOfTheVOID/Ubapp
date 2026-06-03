import Foundation

/// Wraps [HostServer] with President (Scum/Asshole) routing.
final class PresidentServer {
    private(set) var engine = PresidentEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?
    private var statRecorded = false
    private let series = SeriesScore()
    // President plays multiple rounds per match (next_round), so the series
    // counts each round's president — gated separately from the once-per-match
    // stat recording.
    private var seriesRecorded = false

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "president_browser"))
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
    func stop() { server.stop(); resetState() }

    /// Clear all per-session state so the next time the host starts
    /// hosting they get a fresh screen — empty lobby, tutorial vote
    /// available again.
    private func resetState() {
        engine = PresidentEngine()
        guestToPlayer.removeAll(); playerToGuest.removeAll()
        series.reset(); seriesRecorded = false
        statRecorded = false
        emit()
    }
    var guestCount: Int { server.guestCount }

    func hostSetOptions(_ o: PresOptions) {
        engine.setOptions(o); broadcastOptions(); emit()
    }
    func hostStart() {
        seriesRecorded = false
        engine.start()
        broadcastState(); sendHandsPrivately(); broadcastSwapPrompts(); emit()
    }
    func hostNextRound() {
        seriesRecorded = false
        engine.startNextRound()
        broadcastState(); sendHandsPrivately(); broadcastSwapPrompts(); emit()
    }
    func hostNewGame() {
        engine.reset(); statRecorded = false
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

    private func onMessage(from guest: GuestId, raw: String) {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return }
        switch type {
        case "join": handleJoin(guest, json: j)
        case "play":
            if let pid = guestToPlayer[guest] { applyPlay(pid, json: j) }
        case "pass":
            if let pid = guestToPlayer[guest] { applyPass(pid) }
        case "swap":
            if let pid = guestToPlayer[guest] { applySwap(pid, json: j) }
        case "next_round":
            // Anyone can ask, but only honored at gameOver — usually host.
            if engine.phase == .gameOver { hostNextRound() }
        case "set_options":
            break
        case "call_tutorial_vote": if guestToPlayer[guest] != nil { openTutorialVote() }
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
        let name = String(((json["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces).prefix(24))
        guard !name.isEmpty else { return }
        let pid = "g\(guestToPlayer.count + 1)"
        engine.addPlayer(id: pid, name: name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "president"])
        broadcastLobby(); broadcastOptions(); broadcastTutorialState()
        if !series.isEmpty { broadcastSeries() }
        emit()
    }

    private func applyPlay(_ pid: String, json: [String: Any]) {
        guard let cardArr = json["cards"] as? [[String: Any]] else { return }
        var cards: [PresCard] = []
        for c in cardArr {
            guard let s = c["suit"] as? String, let suit = PresSuit(rawValue: s),
                  let r = c["rank"] as? Int else { return }
            cards.append(PresCard(suit: suit, rank: r))
        }
        let err = engine.play(playerId: pid, cards: cards)
        if err == nil {
            broadcastState(); sendHandsPrivately()
            if engine.phase == .gameOver { broadcastOver() }
            emit()
        } else if let g = playerToGuest[pid] {
            send(g, ["type": "error", "message": err!])
        }
    }

    private func applyPass(_ pid: String) {
        let err = engine.pass(playerId: pid)
        if err == nil {
            broadcastState(); emit()
        } else if let g = playerToGuest[pid] {
            send(g, ["type": "error", "message": err!])
        }
    }

    private func applySwap(_ pid: String, json: [String: Any]) {
        guard let cardArr = json["cards"] as? [[String: Any]] else { return }
        var cards: [PresCard] = []
        for c in cardArr {
            guard let s = c["suit"] as? String, let suit = PresSuit(rawValue: s),
                  let r = c["rank"] as? Int else { return }
            cards.append(PresCard(suit: suit, rank: r))
        }
        let err = engine.submitSwap(fromId: pid, cards: cards)
        if err == nil {
            broadcastState(); sendHandsPrivately(); broadcastSwapPrompts(); emit()
        } else if let g = playerToGuest[pid] {
            send(g, ["type": "error", "message": err!])
        }
    }

    private func broadcastOptions() {
        broadcast([
            "type": "options",
            "allowHouseRules": engine.options.allowHouseRules,
            "revolution": engine.options.revolution,
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
        case .swapping: phase = "swapping"
        case .playing: phase = "playing"
        case .gameOver: phase = "gameOver"
        }
        var payload: [String: Any] = [
            "type": "state",
            "phase": phase,
            "currentId": engine.current?.id as Any,
            "roundNumber": engine.roundNumber,
            "lastEvent": engine.lastEvent ?? "",
            "players": engine.players.values.map {
                [
                    "id": $0.id, "name": $0.name, "handCount": $0.hand.count,
                    "rank": $0.rank.rawValue, "finished": $0.finished,
                    "finishOrder": $0.finishOrder,
                ] as [String: Any]
            },
            "seating": engine.seating,
            "passedThisTrick": Array(engine.passedThisTrick),
        ]
        if let t = engine.trick {
            payload["trick"] = comboJSON(t.combo).merging([
                "topPower": t.topPower,
                "leaderId": t.leaderId,
            ]) { $1 }
        }
        if let lp = engine.lastPlay {
            payload["lastPlay"] = [
                "playerId": lp.playerId,
                "cards": lp.cards.map { ["suit": $0.suit.rawValue, "rank": $0.rank] },
                "combo": comboJSON(lp.combo),
            ]
        }
        broadcast(payload)
    }

    private func comboJSON(_ combo: PresCombo) -> [String: Any] {
        switch combo {
        case .single: return ["kind": "single", "length": 1]
        case .pair: return ["kind": "pair", "length": 2]
        case .triple: return ["kind": "triple", "length": 3]
        case .quad: return ["kind": "quad", "length": 4]
        case .runOfPairs(let len): return ["kind": "runOfPairs", "length": len * 2]
        }
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

    private func broadcastSwapPrompts() {
        // Each player gets a private list of swaps requiring their input.
        for p in engine.players.values {
            guard let g = playerToGuest[p.id] else { continue }
            let mine = engine.pendingSwaps.compactMap { sw -> [String: Any]? in
                guard sw.cards == nil, sw.fromId == p.id else { return nil }
                return [
                    "toId": sw.toId,
                    "toName": engine.players[sw.toId]?.name ?? "",
                    "count": sw.count,
                    "giverChooses": sw.giverChooses,
                ]
            }
            send(g, ["type": "swap_prompts", "prompts": mine])
        }
    }

    private func broadcastOver() {
        if !statRecorded {
            statRecorded = true
            var names: [String] = []
            for pid in engine.finishOrder {
                if let p = engine.players[pid] { names.append(p.name) }
            }
            StatsStore.record(gameId: "president", players: names, outcome: "win")
        }
        if !seriesRecorded {
            seriesRecorded = true
            if let presidentId = engine.finishOrder.first, let p = engine.players[presidentId] {
                series.record(p.name); broadcastSeries()
            }
        }
        let rankings = engine.finishOrder.compactMap { pid -> [String: Any]? in
            guard let p = engine.players[pid] else { return nil }
            return ["id": p.id, "name": p.name, "rank": p.rank.rawValue,
                    "finishOrder": p.finishOrder]
        }
        broadcast([
            "type": "over",
            "rankings": rankings,
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
            payload["title"] = GameTutorials.president.title
            payload["sections"] = GameTutorials.president.sectionsJSON()
            payload["menuSections"] = GameTutorials.president.browserMenuSectionsJSON()
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
