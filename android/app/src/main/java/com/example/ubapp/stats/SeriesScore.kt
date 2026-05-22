package com.example.ubapp.stats

/**
 * In-session tally of round outcomes for one game — "the series". Keyed by the
 * same outcome string each server hands to [StatsStore] (e.g. "town"/"mafia",
 * "red"/"blue", "x"/"o"/"draw"), so a series is just the running count of those
 * outcomes within one sitting. Host-owned and reset when the host leaves the
 * game. Pure (no I/O); the server turns [scores]/[rounds] into the
 * `series_state` wire message. Kept byte-equivalent with the Swift SeriesScore.
 */
class SeriesScore {
    private val tally = LinkedHashMap<String, Int>()
    var rounds: Int = 0
        private set

    /** Outcome → number of rounds won, insertion-ordered. */
    val scores: Map<String, Int> get() = tally

    fun record(outcome: String) {
        tally[outcome] = (tally[outcome] ?: 0) + 1
        rounds += 1
    }

    fun reset() {
        tally.clear()
        rounds = 0
    }

    val isEmpty: Boolean get() = rounds == 0

    /** "Series — You 2 · CPU 1 · Draw 1"; empty string before any round. */
    fun banner(): String {
        if (isEmpty) return ""
        return "Series — " + tally.entries.joinToString(" · ") { "${it.key} ${it.value}" }
    }
}
