package com.example.ubapp.games.tag

import android.os.Handler
import android.os.Looper

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
) {
    val engine = TagEngine(selfId)
    private var peerNames: Map<String, String> = emptyMap()
    private var detector: ProximityDetector? = null
    private val handler = Handler(Looper.getMainLooper())
    private var hotPotatoRunnable: Runnable? = null

    var onStateChange: ((TagState) -> Unit)? = null

    init { transport.onInbound = ::handleIncoming }

    fun startHosting(variant: TagVariant, peerNames: Map<String, String>) {
        this.peerNames = peerNames
        val ids = peerNames.keys.shuffled()
        val first = ids.firstOrNull() ?: return
        val now = System.currentTimeMillis()
        val msg = TagMessage.Start(variant, first, now, ids, peerNames)
        transport.send(msg)
        beginRound(variant, first, now, ids)
    }

    private fun handleIncoming(msg: TagMessage) {
        when (msg) {
            is TagMessage.Start -> {
                if (engine.state != null) return
                peerNames = msg.peerNames
                beginRound(msg.variant, msg.startingItId, msg.startTimeMs, msg.peerIds)
            }
            is TagMessage.Tag ->
                if (engine.applyTag(msg.taggerId, msg.victimId)) emit()
            is TagMessage.Unfreeze ->
                if (engine.applyUnfreeze(msg.unfreezerId, msg.victimId)) emit()
            is TagMessage.End -> {
                engine.applyEnd(msg.reason, msg.winnerId); emit(); shutdownRound()
            }
            is TagMessage.Hello -> { /* lobby */ }
        }
    }

    private fun beginRound(variant: TagVariant, startingItId: String, startTimeMs: Long, peerIds: List<String>) {
        engine.start(variant, startingItId, startTimeMs, peerIds, peerNames)
        val det = ProximityDetector(onTouch = ::onProximityTouch)
        detector = det
        proximity.onEvent = { e -> detector?.ingest(e) }
        proximity.start()
        emit()
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
            emit()
        }
        hotPotatoRunnable = r
        handler.postDelayed(r, durationMs)
    }

    private fun emit() { engine.state?.let { onStateChange?.invoke(it) } }

    private fun shutdownRound() {
        hotPotatoRunnable?.let { handler.removeCallbacks(it) }
        hotPotatoRunnable = null
        proximity.stop()
    }

    fun dispose() { shutdownRound(); transport.dispose() }
}
