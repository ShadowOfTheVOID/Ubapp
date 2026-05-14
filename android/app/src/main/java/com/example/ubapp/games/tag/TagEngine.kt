package com.example.ubapp.games.tag

enum class PlayerStatus { RUNNER, IT, FROZEN, ELIMINATED }

class TagPlayerView(val id: String, val displayName: String, var status: PlayerStatus)

class TagState(
    val variant: TagVariant,
    val players: MutableMap<String, TagPlayerView>,
    val startedAtMs: Long,
    val deadlineMs: Long,
) {
    var endReason: String? = null
    var winnerId: String? = null
    val isOver: Boolean get() = endReason != null
    val its get() = players.values.filter { it.status == PlayerStatus.IT }
    val runners get() = players.values.filter { it.status == PlayerStatus.RUNNER }
    val frozen get() = players.values.filter { it.status == PlayerStatus.FROZEN }
    val alive get() = players.values.filter { it.status != PlayerStatus.ELIMINATED }
}

/**
 * Deterministic state machine — given the same `start` + ordered events,
 * every device computes the same state.
 */
class TagEngine(val selfId: String) {
    var state: TagState? = null

    fun start(
        variant: TagVariant, startingItId: String, startTimeMs: Long,
        peerIds: List<String>, displayNames: Map<String, String>,
    ): TagState {
        val players = LinkedHashMap<String, TagPlayerView>()
        for (id in peerIds) {
            val name = displayNames[id] ?: id.take(6)
            players[id] = TagPlayerView(
                id, name,
                if (id == startingItId) PlayerStatus.IT else PlayerStatus.RUNNER,
            )
        }
        val duration = if (variant == TagVariant.HOT_POTATO) 10 * 60_000L else variant.durationMs
        val s = TagState(variant, players, startTimeMs, startTimeMs + duration)
        state = s
        return s
    }

    fun applyTag(taggerId: String, victimId: String): Boolean {
        val s = state ?: return false
        if (s.isOver) return false
        val tagger = s.players[taggerId] ?: return false
        val victim = s.players[victimId] ?: return false
        if (tagger.status != PlayerStatus.IT || victim.status != PlayerStatus.RUNNER) return false
        when (s.variant) {
            TagVariant.CLASSIC, TagVariant.BOMB, TagVariant.HOT_POTATO -> {
                tagger.status = PlayerStatus.RUNNER; victim.status = PlayerStatus.IT
            }
            TagVariant.FREEZE -> {
                victim.status = PlayerStatus.FROZEN
                if (s.runners.isEmpty()) { s.endReason = "all_frozen"; s.winnerId = tagger.id }
            }
            TagVariant.ZOMBIE -> {
                victim.status = PlayerStatus.IT
                if (s.runners.isEmpty()) s.endReason = "last_survivor"
            }
        }
        return true
    }

    fun applyUnfreeze(unfreezerId: String, victimId: String): Boolean {
        val s = state ?: return false
        if (s.isOver || s.variant != TagVariant.FREEZE) return false
        val u = s.players[unfreezerId] ?: return false
        val v = s.players[victimId] ?: return false
        if (u.status != PlayerStatus.RUNNER || v.status != PlayerStatus.FROZEN) return false
        v.status = PlayerStatus.RUNNER
        return true
    }

    fun applyEnd(reason: String, winnerId: String?) {
        val s = state ?: return
        if (s.isOver) return
        s.endReason = reason; s.winnerId = winnerId
    }

    fun hotPotatoTimeout(): Pair<String, String?>? {
        val s = state ?: return null
        if (s.isOver || s.variant != TagVariant.HOT_POTATO) return null
        val me = s.players[selfId] ?: return null
        if (me.status != PlayerStatus.IT) return null
        me.status = PlayerStatus.ELIMINATED
        return "hot_potato_timeout" to s.alive.firstOrNull()?.id
    }
}
