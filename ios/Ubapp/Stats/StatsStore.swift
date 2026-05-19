import SwiftUI

/// One game's aggregate record: how many times it was played and the
/// distribution of outcome keys (e.g. `town` / `mafia`).
struct GameStat: Codable {
    var playCount: Int = 0
    var outcomes: [String: Int] = [:]
}

/// A single finished game, newest-first in `StatsData.recent`.
struct RecentEntry: Codable, Identifiable {
    var id = UUID()
    let gameId: String
    let timestamp: Int64        // epoch milliseconds, host-local
    let players: [String]
    let outcome: String

    private enum CodingKeys: String, CodingKey { case gameId, timestamp, players, outcome }
}

struct StatsData: Codable {
    var version: Int = 1
    var games: [String: GameStat] = [:]
    var recent: [RecentEntry] = []
}

/// Host-local play statistics, persisted as JSON in `UserDefaults`. Mirrors
/// the `AppSettings` singleton pattern. The aggregation is a pure static so
/// it stays byte-equivalent with the Kotlin `StatsStore.applyRecord`.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()
    static let key = "ubapp.stats"
    static let recentCap = 50

    @Published private(set) var data: StatsData

    private init() { data = Self.load() }

    /// Record a finished game with a known outcome. Safe to call from any
    /// actor (servers/sessions) — like `AppSettings.currentHostName`.
    nonisolated static func record(gameId: String, players: [String], outcome: String) {
        persistApplied(gameId: gameId, players: players, outcome: outcome)
    }

    /// Record a game that has no win concept (e.g. Real-time).
    nonisolated static func recordCountOnly(gameId: String, players: [String]) {
        persistApplied(gameId: gameId, players: players, outcome: "played")
    }

    func clear() {
        data = StatsData()
        Self.persist(data)
    }

    // MARK: - Pure aggregation (kept in lockstep with Kotlin applyRecord)

    nonisolated static func apply(
        _ prev: StatsData,
        gameId: String,
        players: [String],
        outcome: String,
        timestampMs: Int64,
        recentCap: Int = 50,
    ) -> StatsData {
        var next = prev
        var stat = next.games[gameId] ?? GameStat()
        stat.playCount += 1
        stat.outcomes[outcome, default: 0] += 1
        next.games[gameId] = stat

        let entry = RecentEntry(
            gameId: gameId, timestamp: timestampMs, players: players, outcome: outcome,
        )
        next.recent.insert(entry, at: 0)
        if next.recent.count > recentCap {
            next.recent = Array(next.recent.prefix(recentCap))
        }
        return next
    }

    // MARK: - Persistence

    private nonisolated static func persistApplied(gameId: String, players: [String], outcome: String) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let updated = apply(
            load(), gameId: gameId, players: players, outcome: outcome, timestampMs: now,
        )
        persist(updated)
        Task { @MainActor in shared.data = updated }
    }

    private nonisolated static func load() -> StatsData {
        guard let raw = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(StatsData.self, from: raw)
        else { return StatsData() }
        return decoded
    }

    private nonisolated static func persist(_ d: StatsData) {
        guard let encoded = try? JSONEncoder().encode(d) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}

/// Display helpers shared by the stat board UI.
enum StatsCatalog {
    /// Pretty game name for a stable `gameId`.
    static func gameName(_ id: String) -> String {
        switch id {
        case "mafia": return "Mafia"
        case "werewolf": return "Werewolf"
        case "imposter": return "Imposter"
        case "codenames": return "Codenames"
        case "crazy_eights": return "Crazy Eights"
        case "secret_hitler": return "Secret Hitler"
        case "tag": return "Tag"
        case "tic_tac_toe": return "Tic-Tac-Toe"
        case "connect_four": return "Connect Four"
        case "realtime": return "Real-time"
        default: return id
        }
    }

    /// Human label for an outcome key.
    static func outcomeLabel(_ key: String) -> String {
        switch key {
        case "town": return "Town"
        case "mafia": return "Mafia"
        case "werewolves": return "Werewolves"
        case "imposter": return "Imposter"
        case "red": return "Red"
        case "blue": return "Blue"
        case "yellow": return "Yellow"
        case "liberal": return "Liberal"
        case "fascist": return "Fascist"
        case "runners": return "Runners"
        case "it": return "It"
        case "timeout": return "Timeout"
        case "x": return "X"
        case "o": return "O"
        case "draw": return "Draw"
        case "win": return "Win"
        case "played": return "Played"
        default: return key.capitalized
        }
    }
}
