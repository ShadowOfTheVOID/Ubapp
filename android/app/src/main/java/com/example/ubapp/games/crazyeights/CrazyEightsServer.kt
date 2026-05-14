package com.example.ubapp.games.crazyeights

import android.content.Context
import com.example.ubapp.social.GuestId
import com.example.ubapp.social.HostServer
import com.example.ubapp.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/** Wraps [HostServer] with Crazy Eights routing. */
class CrazyEightsServer(context: Context, val hostName: String = "Host") {
    val engine = CrazyEightsEngine()
    private val server = HostServer(html = HostServer.htmlAsset(context, "crazy_eights_browser.html"))
    private val guestToPlayer = HashMap<GuestId, String>()
    private val playerToGuest = HashMap<String, GuestId>()
    var onStateChange: (() -> Unit)? = null

    init { server.onMessage = ::onMessage; server.onLeave = ::onLeave }
    companion object { const val HOST_ID = "host" }

    fun start(): String? {
        engine.addPlayer(HOST_ID, hostName, isHost = true)
        val u = server.startServer(); emit(); return u
    }
    fun stop() = server.stopServer()
    val guestCount: Int get() = server.guestCount

    fun hostStart() { engine.start(); broadcastState(); sendHandsPrivately(); emit() }
    fun hostPlay(card: Card, declaredSuit: Suit? = null): String? {
        val err = engine.playCard(HOST_ID, card, declaredSuit)
        if (err == null) {
            broadcastState(); sendHandsPrivately()
            if (engine.phase == CrazyEightsPhase.GAME_OVER) broadcastOver()
            emit()
        }
        return err
    }
    fun hostDraw() { engine.drawOne(HOST_ID); broadcastState(); sendHandsPrivately(); emit() }
    fun hostPass() { engine.passAfterDraw(HOST_ID); broadcastState(); emit() }
    fun hostNewGame() {
        engine.reset(); broadcast(JSONObject().put("type", "reset")); broadcastLobby(); emit()
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
            "draw" -> pid?.let { engine.drawOne(it); broadcastState(); sendHandsPrivately(); emit() }
            "pass" -> pid?.let { engine.passAfterDraw(it); broadcastState(); emit() }
            "call_tutorial_vote" -> openTutorialVote()
            "tutorial_vote" -> pid?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        if (engine.phase == CrazyEightsPhase.LOBBY) {
            engine.removePlayer(pid); engine.tutorialVote.removeVoter(pid); broadcastLobby()
            if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        }
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != CrazyEightsPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already in progress")); return
        }
        val name = j.optString("name").trim(); if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid; playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name))
        broadcastLobby(); broadcastTutorialState(); emit()
    }

    private fun applyPlay(pid: String, j: JSONObject) {
        val suit = Suit.entries.first { it.name.equals(j.getString("suit"), true) }
        val rank = j.getInt("rank")
        val declared: Suit? = if (j.isNull("declaredSuit")) null
            else (j.opt("declaredSuit") as? String)?.let { name ->
                Suit.entries.firstOrNull { it.name.equals(name, true) }
            }
        val err = engine.playCard(pid, Card(suit, rank), declared)
        if (err == null) {
            broadcastState(); sendHandsPrivately()
            if (engine.phase == CrazyEightsPhase.GAME_OVER) broadcastOver()
            emit()
        } else {
            playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
        }
    }

    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost))
        broadcast(JSONObject().put("type", "lobby").put("players", arr))
    }
    private fun broadcastState() {
        val top = engine.topCard?.let { JSONObject().put("suit", it.suit.name.lowercase()).put("rank", it.rank) }
        val playersArr = JSONArray()
        for (p in engine.players.values)
            playersArr.put(JSONObject().put("id", p.id).put("name", p.name).put("handCount", p.hand.size))
        broadcast(JSONObject()
            .put("type", "state")
            .put("currentId", engine.current?.id ?: JSONObject.NULL)
            .put("topCard", top ?: JSONObject.NULL)
            .put("activeSuit", engine.activeSuit?.name?.lowercase() ?: JSONObject.NULL)
            .put("drawCount", engine.drawPile.size)
            .put("justDrew", engine.justDrew)
            .put("lastEvent", engine.lastEvent ?: "")
            .put("players", playersArr))
    }
    private fun sendHandsPrivately() {
        for (p in engine.players.values) {
            if (p.id == HOST_ID) continue
            val guest = playerToGuest[p.id] ?: continue
            val cards = JSONArray()
            for (c in p.hand) cards.put(JSONObject().put("suit", c.suit.name.lowercase()).put("rank", c.rank))
            send(guest, JSONObject().put("type", "hand").put("cards", cards))
        }
    }
    private fun broadcastOver() {
        val arr = JSONArray()
        for (p in engine.players.values) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("handCount", p.hand.size))
        broadcast(JSONObject().put("type", "over").put("winnerId", engine.winnerId ?: JSONObject.NULL).put("players", arr))
    }

    private fun openTutorialVote() {
        if (engine.phase != CrazyEightsPhase.LOBBY) return
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
            p.put("title", GameTutorials.crazyEights.title)
            p.put("sections", JSONArray(GameTutorials.crazyEights.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.crazyEights.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(o: JSONObject) = server.broadcast(o.toString())
    private fun send(g: GuestId, o: JSONObject) = server.send(g, o.toString())
}
