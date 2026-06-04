import Foundation

/// Wraps [HostServer] with Bluff Market routing.
final class BluffMarketServer {
    private(set) var engine = BluffMarketEngine()
    static let hostId = "host"
    let hostName: String

    private let server: HostServer
    private var guestToPlayer: [GuestId: String] = [:]
    private var playerToGuest: [String: GuestId] = [:]

    var onStateChange: (() -> Void)?
    private var statRecorded = false
    private let series = SeriesScore()

    init(server: HostServer? = nil, hostName: String = "Host") {
        self.server = server ?? HostServer(html: HostServer.htmlResource(named: "bluff_market_browser"))
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
        engine = BluffMarketEngine()
        guestToPlayer.removeAll(); playerToGuest.removeAll()
        statRecorded = false
        emit()
    }
    var guestCount: Int { server.guestCount }

    func hostSetOptions(_ o: BluffMarketOptions) {
        engine.setOptions(o); broadcastOptions(); emit()
    }
    func hostStart() {
        engine.start()
        broadcastState(); sendHandsPrivately(); emit()
    }
    func hostNewGame() {
        engine.reset(); statRecorded = false
        broadcast(["type": "reset"]); broadcastLobby(); broadcastTutorialState()
        if !series.isEmpty { broadcastSeries() }
        emit()
    }
    func hostFinalize() {
        engine.finalize()
        broadcastState(); broadcastOver(); emit()
    }
    func hostCallTutorialVote() { openTutorialVote() }
    func hostTutorialVote(_ yes: Bool) { submitTutorialVote(voterId: Self.hostId, yes: yes) }
    func hostDismissTutorial() {
        engine.tutorialVote.markShown(); broadcastTutorialState(); emit()
    }

    private func onMessage(from guest: GuestId, raw: String) {
        guard let data = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String else { return }
        switch type {
        case "join": handleJoin(guest, json: j)
        case "buy":
            if let pid = guestToPlayer[guest] { applyResult(pid, engine.buyFromMarket(playerId: pid)) }
        case "sell":
            if let pid = guestToPlayer[guest], let cid = j["cardId"] as? String {
                applyResult(pid, engine.sellToMarket(playerId: pid, cardId: cid))
            }
        case "propose_trade":
            if let pid = guestToPlayer[guest],
               let target = j["targetId"] as? String,
               let cid = j["cardId"] as? String {
                applyResult(pid, engine.proposeTrade(playerId: pid, targetId: target, cardId: cid))
            }
        case "counter_trade":
            if let pid = guestToPlayer[guest], let cid = j["cardId"] as? String {
                applyResult(pid, engine.counterTrade(playerId: pid, cardId: cid))
            }
        case "decline_trade":
            if let pid = guestToPlayer[guest] { applyResult(pid, engine.declineTrade(playerId: pid)) }
        case "guarantee":
            if let pid = guestToPlayer[guest] { applyResult(pid, engine.useGuarantee(playerId: pid)) }
        case "respond_trade":
            if let pid = guestToPlayer[guest], let accept = j["accept"] as? Bool {
                applyResult(pid, engine.respondTrade(playerId: pid, accept: accept))
            }
        case "finalize":
            // Anyone can request final scoring once phase == scoring, host usually drives it.
            if engine.phase == .scoring { hostFinalize() }
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

    private func applyResult(_ pid: String, _ err: String?) {
        if err == nil {
            broadcastState(); sendHandsPrivately()
            if engine.phase == .scoring { broadcastScores() }
            if engine.phase == .gameOver { broadcastOver() }
            emit()
        } else if let g = playerToGuest[pid] {
            send(g, ["type": "error", "message": err!])
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
        let pid = "p\(guest.value)"
        engine.addPlayer(id: pid, name: name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, ["type": "welcome", "yourId": pid, "yourName": name, "game": "bluff_market"])
        broadcastLobby(); broadcastOptions(); broadcastTutorialState()
        if !series.isEmpty { broadcastSeries() }
        emit()
    }

    private func broadcastOptions() {
        broadcast([
            "type": "options",
            "turnsPerPlayer": engine.options.turnsPerPlayer,
            "twoBombs": engine.options.twoBombs,
            "wildcard": engine.options.wildcard,
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
        case .scoring: phase = "scoring"
        case .gameOver: phase = "gameOver"
        }
        var payload: [String: Any] = [
            "type": "state",
            "phase": phase,
            "currentId": engine.current?.id as Any,
            "marketSize": engine.market.count,
            "lastEvent": engine.lastEvent ?? "",
            "players": engine.players.values.map {
                ["id": $0.id, "name": $0.name, "handCount": $0.hand.count,
                 "coins": $0.coins, "turnsTaken": $0.turnsTaken,
                 "guaranteeUsed": $0.guaranteeUsed] as [String: Any]
            },
            "turnsPerPlayer": engine.options.turnsPerPlayer,
        ]
        if let t = engine.activeTrade {
            // Public: who's in the trade and (only once both committed) the cards.
            var tradeJson: [String: Any] = [
                "proposerId": t.proposerId,
                "targetId": t.targetId,
                "proposerCommitted": t.proposerCardId != nil,
                "targetCommitted": t.targetCardId != nil,
                "revealed": t.revealed,
                "proposerGuarantee": t.proposerGuarantee,
                "targetGuarantee": t.targetGuarantee,
            ]
            if t.proposerAccept != nil { tradeJson["proposerAccept"] = t.proposerAccept! }
            if t.targetAccept != nil { tradeJson["targetAccept"] = t.targetAccept! }
            if t.revealed,
               let pcid = t.proposerCardId, let pc = engine.cardCatalog[pcid],
               let tcid = t.targetCardId, let tc = engine.cardCatalog[tcid] {
                tradeJson["proposerCard"] = cardJson(pc)
                tradeJson["targetCard"] = cardJson(tc)
            }
            payload["trade"] = tradeJson
        }
        broadcast(payload)
    }

    private func cardJson(_ c: BluffCard) -> [String: Any] {
        var kind = "points"; var v: Int = c.points
        switch c.kind {
        case .points: kind = "points"
        case .bomb: kind = "bomb"
        case .wildcard: kind = "wildcard"; v = 0
        }
        return ["id": c.id, "kind": kind, "value": v, "label": c.label]
    }

    private func sendHandsPrivately() {
        for p in engine.players.values {
            guard let g = playerToGuest[p.id] else { continue }
            send(g, [
                "type": "hand",
                "cards": p.hand.map { cardJson($0) },
            ])
        }
    }

    private func broadcastScores() {
        let scores = engine.score()
        broadcast([
            "type": "scores",
            "rows": scores.map { row in
                [
                    "id": row.id, "name": row.name,
                    "total": row.total, "sum": row.sum, "coins": row.coins,
                    "hasBomb": row.hasBomb,
                ] as [String: Any]
            },
        ])
    }

    private func broadcastOver() {
        let scores = engine.score()
        let winner = scores.max(by: { $0.total < $1.total })
        if !statRecorded {
            statRecorded = true
            var names: [String] = []
            if let w = winner { names.append(w.name) }
            for r in scores where r.id != winner?.id { names.append(r.name) }
            StatsStore.record(gameId: "bluff_market", players: names, outcome: "win")
            if let w = winner { series.record(w.name); broadcastSeries() }
        }
        broadcast([
            "type": "over",
            "winnerId": winner?.id as Any,
            "rows": scores.map { row in
                [
                    "id": row.id, "name": row.name,
                    "total": row.total, "sum": row.sum, "coins": row.coins,
                    "hasBomb": row.hasBomb,
                ] as [String: Any]
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
            payload["title"] = GameTutorials.bluffMarket.title
            payload["sections"] = GameTutorials.bluffMarket.sectionsJSON()
            payload["menuSections"] = GameTutorials.bluffMarket.browserMenuSectionsJSON()
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
