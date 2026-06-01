import Foundation

/// In-session tally of round outcomes for one game — "the series". Keyed by the
/// same outcome string each server hands to `StatsStore` (e.g. "town"/"mafia",
/// "red"/"blue", "x"/"o"/"draw"), so a series is just the running count of those
/// outcomes within one sitting. Host-owned and reset when the host leaves the
/// game. Pure (no I/O); the server turns `scores`/`rounds` into the
/// `series_state` wire message. Kept byte-equivalent with the Kotlin SeriesScore.
final class SeriesScore {
    /// Insertion order of outcome keys, so the banner renders them stably.
    private(set) var order: [String] = []
    private var tally: [String: Int] = [:]
    private(set) var rounds = 0

    /// Outcome → number of rounds won, in insertion order.
    var scores: [(key: String, value: Int)] { order.map { ($0, tally[$0] ?? 0) } }

    func record(_ outcome: String) {
        if tally[outcome] == nil { order.append(outcome) }
        tally[outcome, default: 0] += 1
        rounds += 1
    }

    func reset() {
        order.removeAll()
        tally.removeAll()
        rounds = 0
    }

    var isEmpty: Bool { rounds == 0 }

    /// "Series — You 2 · CPU 1 · Draw 1"; empty string before any round.
    func banner() -> String {
        if isEmpty { return "" }
        return "Series — " + scores.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }
}
