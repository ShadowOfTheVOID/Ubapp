import Foundation

/// Glue between proximity detection, the engine, and the network. Owns a
/// [TagTransport] so the host's authoritative engine and every peer's
/// mirror engine apply the same ordered events.
final class TagSession {
    let selfId: String
    let selfDisplayName: String
    let proximity: any ProximitySource
    let transport: any TagTransport
    let engine: TagEngine

    private var peerNames: [String: String] = [:]
    private var detector: ProximityDetector?
    private var hotPotatoTimer: DispatchSourceTimer?

    var onStateChange: ((TagState) -> Void)?

    init(selfId: String, selfDisplayName: String,
         proximity: any ProximitySource, transport: any TagTransport) {
        self.selfId = selfId
        self.selfDisplayName = selfDisplayName
        self.proximity = proximity
        self.transport = transport
        self.engine = TagEngine(selfId: selfId)
        transport.onInbound = { [weak self] msg in self?.handleIncoming(msg) }
    }

    /// Host: pick the starting "it", broadcast Start, kick off the round.
    func startHosting(variant: TagVariant, peerNames: [String: String]) {
        self.peerNames = peerNames
        let ids = Array(peerNames.keys).shuffled()
        guard let first = ids.first else { return }
        let start: TagMessage = .start(
            variant: variant, startingItId: first,
            startTimeMs: Int64(Date().timeIntervalSince1970 * 1000),
            peerIds: ids, peerNames: peerNames)
        transport.send(start)
        beginRound(variant: variant, startingItId: first,
                   startTimeMs: Int64(Date().timeIntervalSince1970 * 1000),
                   peerIds: ids)
    }

    private func handleIncoming(_ msg: TagMessage) {
        switch msg {
        case let .start(variant, startingItId, startTimeMs, peerIds, names):
            if engine.state != nil { return }
            self.peerNames = names
            beginRound(variant: variant, startingItId: startingItId,
                       startTimeMs: startTimeMs, peerIds: peerIds)
        case let .tag(taggerId, victimId, _):
            if engine.applyTag(taggerId: taggerId, victimId: victimId) { emit() }
        case let .unfreeze(unfreezerId, victimId, _):
            if engine.applyUnfreeze(unfreezerId: unfreezerId, victimId: victimId) { emit() }
        case let .end(reason, winnerId):
            engine.applyEnd(reason: reason, winnerId: winnerId)
            emit()
            shutdownRound()
        case .hello, .tutorialCall, .tutorialVote, .tutorialState:
            break // lobby-only, handled by the lobby UI directly
        }
    }

    private func beginRound(variant: TagVariant, startingItId: String,
                            startTimeMs: Int64, peerIds: [String]) {
        engine.start(variant: variant, startingItId: startingItId,
                     startTimeMs: startTimeMs, peerIds: peerIds, displayNames: peerNames)
        let det = ProximityDetector { [weak self] peer in self?.onProximityTouch(peer) }
        self.detector = det
        proximity.onEvent = { [weak self] e in self?.detector?.ingest(e) }
        proximity.start()
        emit()
        if variant == .hotPotato { restartHotPotatoTimer(durationMs: Int(variant.duration * 1000)) }
    }

    private func onProximityTouch(_ peerId: String) {
        guard let state = engine.state, !state.isOver,
              let me = state.players[selfId], let other = state.players[peerId]
        else { return }
        if me.status == .it && other.status == .runner {
            let msg: TagMessage = .tag(taggerId: selfId, victimId: peerId,
                                       timeMs: Int64(Date().timeIntervalSince1970 * 1000))
            if engine.applyTag(taggerId: selfId, victimId: peerId) {
                transport.send(msg)
                detector?.grantImmunity(peerId)
                emit()
                if state.variant == .hotPotato {
                    restartHotPotatoTimer(durationMs: Int(state.variant.duration * 1000))
                }
            }
        } else if state.variant == .freeze &&
                  me.status == .runner && other.status == .frozen {
            let msg: TagMessage = .unfreeze(unfreezerId: selfId, victimId: peerId,
                                            timeMs: Int64(Date().timeIntervalSince1970 * 1000))
            if engine.applyUnfreeze(unfreezerId: selfId, victimId: peerId) {
                transport.send(msg)
                detector?.grantImmunity(peerId)
                emit()
            }
        }
    }

    private func restartHotPotatoTimer(durationMs: Int) {
        hotPotatoTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .milliseconds(durationMs))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if let end = self.engine.hotPotatoTimeout() {
                self.transport.send(.end(reason: end.reason, winnerId: end.winnerId))
                self.emit()
            }
        }
        t.resume()
        hotPotatoTimer = t
    }

    private func emit() { if let s = engine.state { onStateChange?(s) } }

    private func shutdownRound() {
        hotPotatoTimer?.cancel(); hotPotatoTimer = nil
        proximity.stop()
    }

    func dispose() {
        shutdownRound()
        transport.dispose()
    }
}
