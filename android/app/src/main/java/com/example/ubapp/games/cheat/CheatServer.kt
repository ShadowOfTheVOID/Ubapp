package com.example.ubapp.games.cheat

import android.content.Context
import com.example.ubapp.join.LoopbackGuest
import com.example.ubapp.social.GuestId
import com.example.ubapp.social.HostServer
import com.example.ubapp.stats.StatsStore
import com.example.ubapp.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/** Wraps [HostServer] with Cheat routing. */
class CheatServer(context: Context, val hostName: String = "Host") {
    val engine = CheatEngine()
    private val server = HostServer(html = HostServer.htmlAsset(context, "cheat_browser.html"), ctx = context)
    private val appCtx = context.applicationContext
    private val guestToPlayer = HashMap<GuestId, String>()
    private val playerToGuest = HashMap<String, GuestId>()
    var onStateChange: (() -> Unit)? = null
    private var statRecorded = false

    init { server.onMessage = ::onMessage; server.onLeave = ::onLeave }
    companion object { const val HOST_ID = "host" }

    fun start(): String? {
        engine.addPlayer(HOST_ID, hostName, isHost = true)
        val u = server.startServer()
        val local = server.attachLocalGuest()
        guestToPlayer[local] = HOST_ID
        playerToGuest[HOST_ID] = local
        emit()
        return u
    }

    fun makeLoopback(): LoopbackGuest = LoopbackGuest(server)
    fun stop() = server.stopServer()
    val guestCount: Int get() = server.guestCount

    fun hostSetOptions(o: CheatOptions) {
        engine.setOptions(o); broadcastOptions(); emit()
    }
    fun hostStart() { engine.start(); broadcastState(); sendHandsPrivately(); emit() }
    fun hostNewGame() {
        engine.reset(); statRecorded = false
        broadcast(JSONObject().put("type", "reset")); broadcastLobby(); broadcastTutorialState(); emit()
    }
    fun hostCallTutorialVote() = openTutorialVote()
    fun hostTutorialVote(yes: Boolean) = submitTutorialVote(HOST_ID, yes)
    fun hostDismissTutorial() { engine.tutorialVote.markShown(); broadcastTutorialState(); emit() }

    private fun onMessage(guest: GuestId, raw: String) {
        val j = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val pid = guestToPlayer[guest]
        when (j.optString("type")) {
            "join" -> handleJoin(guest, j)
            "play" -> pid?.let { applyPlay(it, j) }
            "bs" -> pid?.let { applyBs(it) }
            "accept_win" -> pid?.let { applyAccept(it) }
            "set_options" -> Unit
            "call_tutorial_vote" -> openTutorialVote()
            "tutorial_vote" -> pid?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        if (engine.phase == CheatPhase.LOBBY) {
            engine.removePlayer(pid); engine.tutorialVote.removeVoter(pid); broadcastLobby()
            if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        }
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != CheatPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already in progress")); return
        }
        val name = j.optString("name").trim(); if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid; playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "cheat"))
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private fun applyPlay(pid: String, j: JSONObject) {
        val rank = j.optInt("claimedRank", -1)
        val arr = j.optJSONArray("cards") ?: return
        val cards = ArrayList<CheatCard>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val suit = CheatSuit.entries.firstOrNull { it.name.equals(o.getString("suit"), true) } ?: return
            cards.add(CheatCard(suit, o.getInt("rank")))
        }
        val err = engine.play(pid, cards, rank)
        if (err == null) {
            broadcastState(); sendHandsPrivately()
            if (engine.phase == CheatPhase.GAME_OVER) broadcastOver()
            emit()
        } else playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
    }

    private fun applyBs(pid: String) {
        val err = engine.callBs(pid)
        if (err == null) {
            broadcastState(); sendHandsPrivately()
            if (engine.phase == CheatPhase.GAME_OVER) broadcastOver()
            emit()
        } else playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
    }

    private fun applyAccept(pid: String) {
        val err = engine.acceptWin(pid)
        if (err == null) {
            broadcastState()
            if (engine.phase == CheatPhase.GAME_OVER) broadcastOver()
            emit()
        } else playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
    }

    private fun broadcastOptions() {
        broadcast(JSONObject().put("type", "options").put("freeClaim", engine.options.freeClaim))
    }

    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost))
        broadcast(JSONObject().put("type", "lobby").put("players", arr))
    }

    private fun broadcastState() {
        val playersArr = JSONArray()
        for (p in engine.players.values)
            playersArr.put(JSONObject().put("id", p.id).put("name", p.name).put("handCount", p.hand.size))
        val phase = when (engine.phase) {
            CheatPhase.LOBBY -> "lobby"
            CheatPhase.PLAYING -> "playing"
            CheatPhase.PENDING_WIN -> "pendingWin"
            CheatPhase.GAME_OVER -> "gameOver"
        }
        val payload = JSONObject()
            .put("type", "state")
            .put("phase", phase)
            .put("currentId", engine.current?.id ?: JSONObject.NULL)
            .put("expectedRank", engine.expectedRank)
            .put("pileSize", engine.pile.size)
            .put("lastEvent", engine.lastEvent ?: "")
            .put("winnerId", engine.winnerId ?: JSONObject.NULL)
            .put("players", playersArr)
        engine.lastPlay?.let {
            payload.put("lastPlay", JSONObject()
                .put("playerId", it.playerId)
                .put("claimedRank", it.claimedRank)
                .put("count", it.count))
        }
        engine.lastReveal?.let { r ->
            val cards = JSONArray()
            for (c in r.cards) cards.put(JSONObject().put("suit", c.suit.name.lowercase()).put("rank", c.rank))
            payload.put("lastReveal", JSONObject()
                .put("callerId", r.callerId)
                .put("accusedId", r.accusedId)
                .put("claimedRank", r.claimedRank)
                .put("truthful", r.truthful)
                .put("loserId", r.loserId)
                .put("cards", cards))
        }
        broadcast(payload)
    }

    private fun sendHandsPrivately() {
        for (p in engine.players.values) {
            val g = playerToGuest[p.id] ?: continue
            val cards = JSONArray()
            for (c in p.hand) cards.put(JSONObject().put("suit", c.suit.name.lowercase()).put("rank", c.rank))
            send(g, JSONObject().put("type", "hand").put("cards", cards))
        }
    }

    private fun broadcastOver() {
        if (!statRecorded) {
            statRecorded = true
            val names = ArrayList<String>()
            engine.winnerId?.let { wid -> engine.players[wid]?.let { names.add(it.name) } }
            for (p in engine.players.values) if (p.id != engine.winnerId) names.add(p.name)
            StatsStore.record(appCtx, "cheat", names, "win")
        }
        val arr = JSONArray()
        for (p in engine.players.values) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("handCount", p.hand.size))
        broadcast(JSONObject().put("type", "over").put("winnerId", engine.winnerId ?: JSONObject.NULL).put("players", arr))
    }

    private fun openTutorialVote() {
        if (engine.phase != CheatPhase.LOBBY) return
        if (engine.tutorialVote.isOpen || engine.tutorialVote.tutorialShown) return
        engine.tutorialVote.open(engine.players.keys); broadcastTutorialState(); emit()
    }
    private fun submitTutorialVote(voterId: String, yes: Boolean) {
        if (!engine.tutorialVote.isOpen) return
        engine.tutorialVote.submit(voterId, yes); broadcastTutorialState(); emit()
    }
    private fun broadcastTutorialState() {
        val v = engine.tutorialVote
        val p = JSONObject().put("type", "tutorial_vote_state")
            .put("isOpen", v.isOpen).put("yesCount", v.yesCount).put("noCount", v.noCount)
            .put("eligibleCount", v.eligibleCount).put("result", v.result ?: JSONObject.NULL)
            .put("tutorialShown", v.tutorialShown)
        if (v.result == true && !v.tutorialShown) {
            p.put("title", GameTutorials.cheat.title)
            p.put("sections", JSONArray(GameTutorials.cheat.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.cheat.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(o: JSONObject) = server.broadcast(o.toString())
    private fun send(g: GuestId, o: JSONObject) = server.send(g, o.toString())
}
