package com.example.jamboree.stats

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** One game's aggregate record. */
data class GameStat(val playCount: Int, val outcomes: Map<String, Int>)

/** A single finished game, newest-first in [StatsData.recent]. */
data class RecentEntry(
    val gameId: String,
    val timestamp: Long,        // epoch millis, host-local
    val players: List<String>,
    val outcome: String,
)

data class StatsData(
    val version: Int = 1,
    val games: Map<String, GameStat> = emptyMap(),
    val recent: List<RecentEntry> = emptyList(),
)

/**
 * Host-local play statistics, persisted as JSON in the shared
 * `jamboree.settings` prefs file (same store as [com.example.jamboree.settings.AppSettings]).
 * [applyRecord] is pure and kept byte-equivalent with the Swift
 * `StatsStore.apply` — it is the regression net for both platforms.
 */
object StatsStore {
    private const val PREFS = "jamboree.settings"
    private const val KEY = "stats"
    const val RECENT_CAP = 50

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun record(ctx: Context, gameId: String, players: List<String>, outcome: String) {
        val updated = applyRecord(
            snapshot(ctx), gameId, players, outcome, System.currentTimeMillis(),
        )
        prefs(ctx).edit().putString(KEY, encode(updated).toString()).apply()
    }

    fun recordCountOnly(ctx: Context, gameId: String, players: List<String>) =
        record(ctx, gameId, players, "played")

    fun clear(ctx: Context) {
        prefs(ctx).edit().remove(KEY).apply()
    }

    fun snapshot(ctx: Context): StatsData {
        val raw = prefs(ctx).getString(KEY, null) ?: return StatsData()
        return runCatching { decode(JSONObject(raw)) }.getOrDefault(StatsData())
    }

    // ---- Pure aggregation (lockstep with Swift StatsStore.apply) ----

    fun applyRecord(
        prev: StatsData,
        gameId: String,
        players: List<String>,
        outcome: String,
        timestampMs: Long,
        recentCap: Int = RECENT_CAP,
    ): StatsData {
        val prevStat = prev.games[gameId] ?: GameStat(0, emptyMap())
        val outcomes = prevStat.outcomes.toMutableMap()
        outcomes[outcome] = (outcomes[outcome] ?: 0) + 1
        val games = prev.games.toMutableMap()
        games[gameId] = GameStat(prevStat.playCount + 1, outcomes)

        val recent = ArrayList<RecentEntry>(prev.recent.size + 1)
        recent.add(RecentEntry(gameId, timestampMs, players, outcome))
        recent.addAll(prev.recent)
        val capped = if (recent.size > recentCap) recent.subList(0, recentCap).toList() else recent

        return StatsData(prev.version, games, capped)
    }

    // ---- JSON ----

    private fun encode(d: StatsData): JSONObject {
        val games = JSONObject()
        for ((id, s) in d.games) {
            val outcomes = JSONObject()
            for ((k, v) in s.outcomes) outcomes.put(k, v)
            games.put(id, JSONObject().put("playCount", s.playCount).put("outcomes", outcomes))
        }
        val recent = JSONArray()
        for (e in d.recent) {
            recent.put(
                JSONObject()
                    .put("gameId", e.gameId)
                    .put("timestamp", e.timestamp)
                    .put("players", JSONArray(e.players))
                    .put("outcome", e.outcome),
            )
        }
        return JSONObject().put("version", d.version).put("games", games).put("recent", recent)
    }

    private fun decode(o: JSONObject): StatsData {
        val games = HashMap<String, GameStat>()
        val gObj = o.optJSONObject("games") ?: JSONObject()
        for (id in gObj.keys()) {
            val s = gObj.getJSONObject(id)
            val outcomes = HashMap<String, Int>()
            val oc = s.optJSONObject("outcomes") ?: JSONObject()
            for (k in oc.keys()) outcomes[k] = oc.getInt(k)
            games[id] = GameStat(s.optInt("playCount"), outcomes)
        }
        val recent = ArrayList<RecentEntry>()
        val rArr = o.optJSONArray("recent") ?: JSONArray()
        for (i in 0 until rArr.length()) {
            val e = rArr.getJSONObject(i)
            val players = ArrayList<String>()
            val pArr = e.optJSONArray("players") ?: JSONArray()
            for (j in 0 until pArr.length()) players.add(pArr.getString(j))
            recent.add(
                RecentEntry(
                    e.getString("gameId"), e.getLong("timestamp"), players, e.getString("outcome"),
                ),
            )
        }
        return StatsData(o.optInt("version", 1), games, recent)
    }

    // ---- Display helpers (shared by the stat board UI) ----

    fun gameName(id: String): String = when (id) {
        "mafia" -> "Mafia"
        "werewolf" -> "Werewolf"
        "imposter" -> "Imposter"
        "codenames" -> "Codenames"
        "crazy_eights" -> "Crazy Eights"
        "cheat" -> "Cheat"
        "president" -> "President"
        "bluff_market" -> "Bluff Market"
        "secret_hitler" -> "Secret Hitler"
        "tag" -> "Tag"
        "tic_tac_toe" -> "Tic-Tac-Toe"
        "connect_four" -> "Connect Four"
        "realtime" -> "Real-time"
        else -> id
    }

    fun outcomeLabel(key: String): String = when (key) {
        "town" -> "Town"
        "mafia" -> "Mafia"
        "werewolves" -> "Werewolves"
        "imposter" -> "Imposter"
        "red" -> "Red"
        "blue" -> "Blue"
        "yellow" -> "Yellow"
        "liberal" -> "Liberal"
        "fascist" -> "Fascist"
        "runners" -> "Runners"
        "it" -> "It"
        "timeout" -> "Timeout"
        "x" -> "X"
        "o" -> "O"
        "draw" -> "Draw"
        "win" -> "Win"
        "played" -> "Played"
        else -> key.replaceFirstChar { it.uppercase() }
    }
}
