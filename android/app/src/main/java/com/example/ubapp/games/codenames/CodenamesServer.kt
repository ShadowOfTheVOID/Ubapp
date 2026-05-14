package com.example.ubapp.games.codenames

import android.content.Context
import com.example.ubapp.social.GuestId
import com.example.ubapp.social.HostServer
import com.example.ubapp.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/** Wraps [HostServer] with Codenames-specific routing. */
class CodenamesServer(context: Context, val hostName: String = "Host") {
    val engine = CodenamesEngine()
    private val server = HostServer(html = HostServer.htmlAsset(context, "codenames_browser.html"))
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

    fun hostJoinTeam(team: Team) { engine.setTeam(HOST_ID, team); broadcastLobby(); sendRolesToAll(); emit() }
    fun hostSetSpymaster(on: Boolean) { engine.setSpymaster(HOST_ID, on); broadcastLobby(); sendRolesToAll(); emit() }
    fun hostStart() { engine.start(); broadcastState(); sendRolesToAll(); emit() }
    fun hostSubmitClue(clue: String, number: Int) { engine.submitClue(HOST_ID, clue, number); broadcastState(); emit() }
    fun hostGuess(index: Int) { engine.guess(HOST_ID, index); broadcastState(); emit() }
    fun hostEndTurn() { engine.endTurn(HOST_ID); broadcastState(); emit() }
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
            "team" -> pid?.let {
                engine.setTeam(it, Team.valueOf(j.getString("team").uppercase()))
                broadcastLobby(); sendRolesToAll(); emit()
            }
            "spymaster" -> pid?.let {
                engine.setSpymaster(it, j.getBoolean("on")); broadcastLobby(); sendRolesToAll(); emit()
            }
            "clue" -> pid?.let {
                engine.submitClue(it, j.getString("clue"), j.getInt("number"))
                broadcastState(); emit()
            }
            "guess" -> pid?.let { engine.guess(it, j.getInt("index")); broadcastState(); emit() }
            "end_turn" -> pid?.let { engine.endTurn(it); broadcastState(); emit() }
            "call_tutorial_vote" -> openTutorialVote()
            "tutorial_vote" -> pid?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        if (engine.phase == CodenamesPhase.LOBBY) {
            engine.removePlayer(pid); engine.tutorialVote.removeVoter(pid); broadcastLobby()
            if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        }
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != CodenamesPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already in progress")); return
        }
        val name = j.optString("name").trim(); if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid; playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name))
        broadcastLobby(); broadcastTutorialState(); emit()
    }

    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) {
            arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost)
                .put("isSpymaster", p.isSpymaster)
                .put("team", p.team?.name?.lowercase() ?: JSONObject.NULL))
        }
        broadcast(JSONObject().put("type", "lobby").put("players", arr).put("canStart", engine.canStart))
    }

    private fun broadcastState() {
        val arr = JSONArray()
        for (c in engine.board) {
            val o = JSONObject().put("word", c.word).put("revealed", c.revealed)
            if (c.revealed) o.put("kind", c.kind.name.lowercase())
            arr.put(o)
        }
        broadcast(JSONObject()
            .put("type", "state")
            .put("phase", if (engine.phase == CodenamesPhase.PLAYING) "playing" else "gameOver")
            .put("currentTeam", engine.currentTeam.name.lowercase())
            .put("currentClue", engine.currentClue ?: JSONObject.NULL)
            .put("currentNumber", engine.currentNumber)
            .put("guessesLeft", engine.guessesLeftThisTurn)
            .put("redLeft", engine.cardsLeftFor(Team.RED))
            .put("blueLeft", engine.cardsLeftFor(Team.BLUE))
            .put("board", arr)
            .put("winner", engine.winner?.name?.lowercase() ?: JSONObject.NULL)
            .put("endReason", engine.endReason ?: JSONObject.NULL)
            .put("lastEvent", engine.lastEvent ?: ""))
    }

    private fun sendRolesToAll() {
        for (p in engine.players.values) {
            if (p.id == HOST_ID) continue
            val guest = playerToGuest[p.id] ?: continue
            val payload = JSONObject()
                .put("type", "role")
                .put("team", p.team?.name?.lowercase() ?: JSONObject.NULL)
                .put("isSpymaster", p.isSpymaster)
            if (p.isSpymaster && engine.board.isNotEmpty()) {
                payload.put("smView", JSONArray(engine.board.map { JSONObject().put("kind", it.kind.name.lowercase()) }))
            }
            send(guest, payload)
        }
    }

    private fun openTutorialVote() {
        if (engine.phase != CodenamesPhase.LOBBY) return
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
            p.put("title", GameTutorials.codenames.title)
            p.put("sections", JSONArray(GameTutorials.codenames.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.codenames.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(o: JSONObject) = server.broadcast(o.toString())
    private fun send(g: GuestId, o: JSONObject) = server.send(g, o.toString())
}
