import Foundation

enum PlayerStatus { case runner, it, frozen, eliminated }

final class TagPlayerView {
    let id: String
    let displayName: String
    var status: PlayerStatus
    init(id: String, displayName: String, status: PlayerStatus) {
        self.id = id; self.displayName = displayName; self.status = status
    }
}

final class TagState {
    let variant: TagVariant
    var players: [String: TagPlayerView]
    let startedAtMs: Int64
    let deadlineMs: Int64
    var endReason: String?
    var winnerId: String?

    init(variant: TagVariant, players: [String: TagPlayerView], startedAtMs: Int64, deadlineMs: Int64) {
        self.variant = variant; self.players = players
        self.startedAtMs = startedAtMs; self.deadlineMs = deadlineMs
    }

    var isOver: Bool { endReason != nil }
    var its: [TagPlayerView] { players.values.filter { $0.status == .it } }
    var runners: [TagPlayerView] { players.values.filter { $0.status == .runner } }
    var frozen: [TagPlayerView] { players.values.filter { $0.status == .frozen } }
    var alive: [TagPlayerView] { players.values.filter { $0.status != .eliminated } }
}

/// Deterministic state machine — given the same `start` + ordered events,
/// every device computes the same state.
final class TagEngine {
    let selfId: String
    var state: TagState?

    init(selfId: String) { self.selfId = selfId }

    @discardableResult
    func start(variant: TagVariant, startingItId: String, startTimeMs: Int64,
               peerIds: [String], displayNames: [String: String]) -> TagState {
        var players: [String: TagPlayerView] = [:]
        for id in peerIds {
            let name = displayNames[id] ?? String(id.prefix(6))
            players[id] = TagPlayerView(
                id: id, displayName: name,
                status: id == startingItId ? .it : .runner)
        }
        let durationMs: Int64 = variant == .hotPotato
            ? 10 * 60 * 1000
            : Int64(variant.duration * 1000)
        let s = TagState(variant: variant, players: players,
                         startedAtMs: startTimeMs, deadlineMs: startTimeMs + durationMs)
        state = s
        return s
    }

    @discardableResult
    func applyTag(taggerId: String, victimId: String) -> Bool {
        guard let s = state, !s.isOver,
              let tagger = s.players[taggerId], let victim = s.players[victimId],
              tagger.status == .it, victim.status == .runner else { return false }
        switch s.variant {
        case .classic, .bomb, .hotPotato:
            tagger.status = .runner
            victim.status = .it
        case .freeze:
            victim.status = .frozen
            if s.runners.isEmpty { s.endReason = "all_frozen"; s.winnerId = tagger.id }
        case .zombie:
            victim.status = .it
            if s.runners.isEmpty { s.endReason = "last_survivor" }
        }
        return true
    }

    @discardableResult
    func applyUnfreeze(unfreezerId: String, victimId: String) -> Bool {
        guard let s = state, !s.isOver, s.variant == .freeze,
              let u = s.players[unfreezerId], let v = s.players[victimId],
              u.status == .runner, v.status == .frozen else { return false }
        v.status = .runner
        return true
    }

    func applyEnd(reason: String, winnerId: String?) {
        guard let s = state, !s.isOver else { return }
        s.endReason = reason
        s.winnerId = winnerId
    }

    /// Hot-potato only: if this device is "it" when the per-tag countdown expires.
    func hotPotatoTimeout() -> (reason: String, winnerId: String?)? {
        guard let s = state, !s.isOver, s.variant == .hotPotato,
              let me = s.players[selfId], me.status == .it else { return nil }
        me.status = .eliminated
        return ("hot_potato_timeout", s.alive.first?.id)
    }
}
