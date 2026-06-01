package com.example.jamboree.games.tag

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.example.jamboree.stats.StatsStore

/**
 * Glue between proximity detection, the engine, and the network. Owns a
 * [TagTransport] so the host's authoritative engine and every peer's mirror
 * engine apply the same ordered events.
 */
class TagSession(
    val selfId: String,
    val selfDisplayName: String,
    val proximity: ProximitySource,
    val transport: TagTransport,
    private val appContext: Context? = null,
) {
    val engine = TagEngine(selfId)
    private var peerNames: Map<String, String> = emptyMap()
    private var detector: ProximityDetector? = null
    private val handler = Handler(Looper.getMainLooper())
    private var hotPotatoRunnable: Runnable? = null
    private var isHost = false
    private var statRecorded = false

    var onStateChange: ((TagState) -> Unit)? = null

    init { transport.onInbound = ::handleIncoming }

    fun startHosting(variant: TagVariant, peerNames: Map<String, String>,
                     durationOverrideSec: Int? = null) {
        isHost = true
        this.peerNames = peerNames
        val ids = peerNames.keys.shuffled()
        val first = ids.firstOrNull() ?: return
        val now = System.currentTimeMillis()
        val msg = TagMessage.Start(variant, first, now, ids, peerNames, durationOverrideSec)
        transport.send(msg)
        beginRound(variant, first, now, ids, durationOverrideSec)
    }

    private fun handleIncoming(msg: TagMessage) {
        when (msg) {
            is TagMessage.Start -> {
                if (engine.state != null) return
                peerNames = msg.peerNames
                beginRound(msg.variant, msg.startingItId, msg.startTimeMs, msg.peerIds, msg.durationOverrideSec)
            }
            is TagMessage.Tag ->
                if (engine.applyTag(msg.taggerId, msg.victimId)) emit()
            is TagMessage.Unfreeze ->
                if (engine.applyUnfreeze(msg.unfreezerId, msg.victimId)) emit()
            is TagMessage.End -> {
                engine.applyEnd(msg.reason, msg.winnerId); emit(); shutdownRound()
            }
            is TagMessage.Hello -> { /* lobby */ }
            is TagMessage.TutorialCall,
            is TagMessage.TutorialVote,
            is TagMessage.TutorialState -> { /* tutorial vote is not used by Tag */ }
        }
    }

    private fun beginRound(variant: TagVariant, startingItId: String, startTimeMs: Long,
                           peerIds: List<String>, durationOverrideSec: Int? = null) {
        engine.start(variant, startingItId, startTimeMs, peerIds, peerNames, durationOverrideSec)
        val det = ProximityDetector(onTouch = ::onProximityTouch)
        detector = det
        proximity.onEvent = { e -> detector?.ingest(e) }
        proximity.start()
        emit()
        // Hot Potato uses the per-tag countdown — keep the variant default
        // even when the round duration was overridden.
        if (variant == TagVariant.HOT_POTATO) restartHotPotatoTimer(variant.durationMs)
    }

    private fun onProximityTouch(peerId: String) {
        val state = engine.state ?: return
        if (state.isOver) return
        val me = state.players[selfId] ?: return
        val other = state.players[peerId] ?: return
        if (me.status == PlayerStatus.IT && other.status == PlayerStatus.RUNNER) {
            val msg = TagMessage.Tag(selfId, peerId, System.currentTimeMillis())
            if (engine.applyTag(selfId, peerId)) {
                transport.send(msg); detector?.grantImmunity(peerId); emit()
                if (state.variant == TagVariant.HOT_POTATO) restartHotPotatoTimer(state.variant.durationMs)
            }
        } else if (state.variant == TagVariant.FREEZE &&
                   me.status == PlayerStatus.RUNNER && other.status == PlayerStatus.FROZEN) {
            val msg = TagMessage.Unfreeze(selfId, peerId, System.currentTimeMillis())
            if (engine.applyUnfreeze(selfId, peerId)) {
                transport.send(msg); detector?.grantImmunity(peerId); emit()
            }
        }
    }

    private fun restartHotPotatoTimer(durationMs: Long) {
        hotPotatoRunnable?.let { handler.removeCallbacks(it) }
        val r = Runnable {
            val end = engine.hotPotatoTimeout() ?: return@Runnable
            transport.send(TagMessage.End(end.first, end.second))
            recordTagResult(end.first)
            emit()
        }
        hotPotatoRunnable = r
        handler.postDelayed(r, durationMs)
    }

    private fun emit() {
        engine.state?.let { s ->
            if (s.isOver) recordTagResult(s.endReason)
            onStateChange?.invoke(s)
        }
    }

    /** Records the finished round once, host-only. Tag is app-peer only; the
     *  host is the device that called [startHosting]. */
    private fun recordTagResult(reason: String?) {
        if (!isHost || statRecorded) return
        val ctx = appContext ?: return
        val s = engine.state ?: return
        statRecorded = true
        StatsStore.record(ctx, "tag", s.players.values.map { it.displayName }, tagOutcome(reason))
    }

    private fun tagOutcome(reason: String?): String = when (reason) {
        "all_frozen" -> "it"
        "last_survivor", "hot_potato_timeout" -> "runners"
        else -> "timeout"
    }

    private fun shutdownRound() {
        hotPotatoRunnable?.let { handler.removeCallbacks(it) }
        hotPotatoRunnable = null
        proximity.stop()
    }

    fun dispose() { shutdownRound(); transport.dispose() }
}
