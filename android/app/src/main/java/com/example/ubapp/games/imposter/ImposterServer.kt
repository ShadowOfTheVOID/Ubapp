package com.example.ubapp.games.imposter

import android.content.Context
import com.example.ubapp.join.LoopbackGuest
import com.example.ubapp.social.GuestId
import com.example.ubapp.social.HostServer
import com.example.ubapp.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/** Wraps [HostServer] with Imposter-specific routing. */
class ImposterServer(context: Context, val hostName: String = "Host") {
    val engine = ImposterEngine()
    private val server = HostServer(html = HostServer.htmlAsset(context, "imposter_browser.html"), ctx = context)
    private val guestToPlayer = HashMap<GuestId, String>()
    private val playerToGuest = HashMap<String, GuestId>()
    var onStateChange: (() -> Unit)? = null

    init {
        server.onMessage = ::onMessage
        server.onLeave = ::onLeave
    }

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

    /** In-process pipe for the host's own player screen. */
    fun makeLoopback(): LoopbackGuest = LoopbackGuest(server)

    fun stop() = server.stopServer()
    val guestCount: Int get() = server.guestCount

    fun hostSetOptions(o: ImposterOptions) {
        engine.setOptions(o)
        broadcastOptions(); emit()
    }
    fun hostStart(category: String? = null) {
        engine.start(category)
        sendRolesPrivately(); emit()
    }
    fun hostBeginVoting() {
        engine.beginVoting(); broadcast(JSONObject().put("type", "voting")); emit()
    }
    fun hostVote(targetId: String?) = applyVote(HOST_ID, targetId)
    fun hostNewRound() {
        engine.reset(); broadcast(JSONObject().put("type", "reset")); broadcastLobby(); emit()
    }
    fun hostCallTutorialVote() = openTutorialVote()
    fun hostTutorialVote(yes: Boolean) = submitTutorialVote(HOST_ID, yes)
    fun hostDismissTutorial() { engine.tutorialVote.markShown(); broadcastTutorialState(); emit() }

    private fun onMessage(guest: GuestId, raw: String) {
        val j = runCatching { JSONObject(raw) }.getOrNull() ?: return
        when (j.optString("type")) {
            "join" -> handleJoin(guest, j)
            "vote" -> guestToPlayer[guest]?.let {
                applyVote(it, if (j.isNull("targetId")) null else j.getString("targetId"))
            }
            // Only the host (which never connects over WebSocket) can mutate
            // options — ignore inbound `set_options` from guests.
            "set_options" -> Unit
            "call_tutorial_vote" -> openTutorialVote()
            "tutorial_vote" -> guestToPlayer[guest]?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        engine.removePlayer(pid)
        engine.tutorialVote.removeVoter(pid)
        broadcastLobby()
        if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != ImposterPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already in progress"))
            return
        }
        val name = j.optString("name").trim()
        if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid; playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "imposter"))
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private fun applyVote(voterId: String, targetId: String?) {
        val ready = engine.submitVote(voterId, targetId)
        emit()
        if (ready) { engine.resolveVotes(); broadcastResult(); emit() }
    }

    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost))
        broadcast(JSONObject().put("type", "lobby").put("players", arr).put("canStart", engine.canStart))
    }
    private fun sendRolesPrivately() {
        val hideCat = engine.options.hideCategory
        // Includes the host: it plays through its own in-process loopback
        // guest, so it must receive the same private role message.
        for (p in engine.players.values) {
            val guest = playerToGuest[p.id] ?: continue
            val hide = p.isImposter && hideCat
            val payload = JSONObject()
                .put("type", "role")
                .put("category", if (hide) "" else engine.category)
                .put("hideCategory", hide)
                .put("isImposter", p.isImposter)
            if (!p.isImposter) {
                payload.put("word", engine.secretWord)
            } else if (p.decoyWord != null) {
                payload.put("word", p.decoyWord).put("isDecoy", true)
            }
            send(guest, payload)
        }
    }
    private fun broadcastOptions() {
        val o = engine.options
        broadcast(JSONObject()
            .put("type", "options")
            .put("imposterCount", o.imposterCount)
            .put("decoyWord", o.decoyWord)
            .put("hideCategory", o.hideCategory)
            .put("mixedPool", o.mixedPool)
            .put("maxImposterCount", engine.maxImposterCount))
    }
    private fun broadcastResult() {
        val arr = JSONArray()
        for (p in engine.players.values) {
            arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isImposter", p.isImposter))
        }
        val imps = JSONArray(); for (id in engine.imposterIds) imps.put(id)
        broadcast(JSONObject()
            .put("type", "result")
            .put("winner", if (engine.winner == ImposterWinner.TOWN) "town" else "imposter")
            .put("imposterIds", imps)
            .put("mostVotedId", engine.mostVotedId ?: JSONObject.NULL)
            .put("imposterCaught", engine.imposterCaught ?: JSONObject.NULL)
            .put("word", engine.secretWord).put("category", engine.category)
            .put("players", arr))
    }

    private fun openTutorialVote() {
        if (engine.phase != ImposterPhase.LOBBY) return
        if (engine.tutorialVote.isOpen || engine.tutorialVote.tutorialShown) return
        engine.tutorialVote.open(engine.players.keys); broadcastTutorialState(); emit()
    }
    private fun submitTutorialVote(voterId: String, yes: Boolean) {
        if (!engine.tutorialVote.isOpen) return
        engine.tutorialVote.submit(voterId, yes); broadcastTutorialState(); emit()
    }
    private fun broadcastTutorialState() {
        val v = engine.tutorialVote
        val p = JSONObject()
            .put("type", "tutorial_vote_state")
            .put("isOpen", v.isOpen).put("yesCount", v.yesCount).put("noCount", v.noCount)
            .put("eligibleCount", v.eligibleCount).put("result", v.result ?: JSONObject.NULL)
            .put("tutorialShown", v.tutorialShown)
        if (v.result == true && !v.tutorialShown) {
            p.put("title", GameTutorials.imposter.title)
            p.put("sections", JSONArray(GameTutorials.imposter.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.imposter.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(o: JSONObject) = server.broadcast(o.toString())
    private fun send(g: GuestId, o: JSONObject) = server.send(g, o.toString())
}
