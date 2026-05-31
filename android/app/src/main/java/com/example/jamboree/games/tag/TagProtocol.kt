package com.example.ubapp.games.tag

import org.json.JSONArray
import org.json.JSONObject

enum class TagVariant(
    val displayName: String,
    val tagline: String,
    /** Default round length in ms. Hot potato uses this as the per-tag countdown;
     *  bomb uses it as the hidden bomb timer. */
    val durationMs: Long,
) {
    CLASSIC("Classic", "Tagger transfers the role on contact.", 5 * 60_000L),
    FREEZE("Freeze tag", "Tagged players freeze. Teammates can unfreeze them.", 5 * 60_000L),
    ZOMBIE("Zombie", "Tagged players become it too. Last survivor wins.", 5 * 60_000L),
    HOT_POTATO("Hot potato", "It must tag before the timer runs out — or they lose.", 30_000L),
    BOMB("Bomb", "Only it knows their role. Tag before the hidden timer ends.", 3 * 60_000L);

    val hasEarlyEnd: Boolean get() = this != CLASSIC
    val hidesIt: Boolean get() = this == BOMB
}

/** Line-oriented JSON messages dispatched on `type`. */
sealed class TagMessage {
    abstract fun toJson(): JSONObject
    fun encode(): String = toJson().toString()

    data class Hello(val peerId: String, val displayName: String) : TagMessage() {
        override fun toJson() = JSONObject().put("type", "hello").put("peerId", peerId).put("displayName", displayName)
    }
    data class Start(
        val variant: TagVariant, val startingItId: String, val startTimeMs: Long,
        val peerIds: List<String>, val peerNames: Map<String, String>,
        val durationOverrideSec: Int? = null,
    ) : TagMessage() {
        override fun toJson() = JSONObject().apply {
            put("type", "start"); put("variant", variant.name.lowercase())
            put("startingItId", startingItId); put("startTimeMs", startTimeMs)
            put("peerIds", JSONArray(peerIds))
            put("peerNames", JSONObject(peerNames as Map<*, *>))
            durationOverrideSec?.let { put("durationOverrideSec", it) }
        }
    }
    data class Tag(val taggerId: String, val victimId: String, val timeMs: Long) : TagMessage() {
        override fun toJson() = JSONObject()
            .put("type", "tag").put("taggerId", taggerId).put("victimId", victimId).put("timeMs", timeMs)
    }
    data class Unfreeze(val unfreezerId: String, val victimId: String, val timeMs: Long) : TagMessage() {
        override fun toJson() = JSONObject()
            .put("type", "unfreeze").put("unfreezerId", unfreezerId).put("victimId", victimId).put("timeMs", timeMs)
    }
    data class End(val reason: String, val winnerId: String?) : TagMessage() {
        override fun toJson() = JSONObject().put("type", "end").put("reason", reason)
            .put("winnerId", winnerId ?: JSONObject.NULL)
    }
    object TutorialCall : TagMessage() {
        override fun toJson() = JSONObject().put("type", "tutorial_call")
    }
    data class TutorialVote(val voterId: String, val yes: Boolean) : TagMessage() {
        override fun toJson() = JSONObject()
            .put("type", "tutorial_vote").put("voterId", voterId).put("yes", yes)
    }
    data class TutorialState(
        val isOpen: Boolean, val yesCount: Int, val noCount: Int,
        val eligibleCount: Int, val result: Boolean?, val tutorialShown: Boolean,
    ) : TagMessage() {
        override fun toJson() = JSONObject()
            .put("type", "tutorial_state").put("isOpen", isOpen)
            .put("yesCount", yesCount).put("noCount", noCount)
            .put("eligibleCount", eligibleCount)
            .put("result", result ?: JSONObject.NULL)
            .put("tutorialShown", tutorialShown)
    }

    companion object {
        fun decode(raw: String): TagMessage = decode(JSONObject(raw))

        /** Decode from an already-parsed object — used by the app-peer join
         *  path, which carries Tag messages over the same `GuestLink` JSON
         *  channel browser-tier games use. */
        fun decode(j: JSONObject): TagMessage {
            return when (j.getString("type")) {
                "hello" -> Hello(j.getString("peerId"), j.getString("displayName"))
                "start" -> {
                    val ids = j.getJSONArray("peerIds").let { arr -> List(arr.length()) { arr.getString(it) } }
                    val names = j.optJSONObject("peerNames")?.let { obj ->
                        obj.keys().asSequence().associateWith { obj.getString(it) }
                    } ?: emptyMap()
                    Start(
                        variant = TagVariant.entries.first { it.name.equals(j.getString("variant"), true)
                            || it.name.replace("_", "").equals(j.getString("variant"), true) },
                        startingItId = j.getString("startingItId"),
                        startTimeMs = j.getLong("startTimeMs"),
                        peerIds = ids, peerNames = names,
                        durationOverrideSec = if (j.has("durationOverrideSec") && !j.isNull("durationOverrideSec"))
                            j.getInt("durationOverrideSec") else null,
                    )
                }
                "tag" -> Tag(j.getString("taggerId"), j.getString("victimId"), j.getLong("timeMs"))
                "unfreeze" -> Unfreeze(j.getString("unfreezerId"), j.getString("victimId"), j.getLong("timeMs"))
                "end" -> End(j.getString("reason"), if (j.isNull("winnerId")) null else j.getString("winnerId"))
                "tutorial_call" -> TutorialCall
                "tutorial_vote" -> TutorialVote(j.getString("voterId"), j.getBoolean("yes"))
                "tutorial_state" -> TutorialState(
                    isOpen = j.getBoolean("isOpen"),
                    yesCount = j.getInt("yesCount"), noCount = j.getInt("noCount"),
                    eligibleCount = j.getInt("eligibleCount"),
                    result = if (j.isNull("result")) null else j.getBoolean("result"),
                    tutorialShown = j.getBoolean("tutorialShown"),
                )
                else -> throw IllegalArgumentException("Unknown TagMessage: ${j.getString("type")}")
            }
        }
    }
}
