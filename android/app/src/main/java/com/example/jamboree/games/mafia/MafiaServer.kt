package com.example.jamboree.games.mafia

import android.content.Context
import com.example.jamboree.join.LoopbackGuest
import com.example.jamboree.social.GuestId
import com.example.jamboree.social.HostServer
import com.example.jamboree.stats.StatsStore
import com.example.jamboree.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/**
 * Wraps [HostServer] with Mafia-specific routing. Owns the engine, fans out
 * the right private/public messages, and converts incoming guest commands
 * into engine calls. Mirrors lib/games/mafia/mafia_server.dart.
 */
class MafiaServer(context: Context, val hostName: String = "Host") {
    var engine = MafiaEngine(); private set
    private val server = HostServer(html = HostServer.htmlAsset(context, "mafia_browser.html"), ctx = context)
    private val appCtx = context.applicationContext
    private val guestToPlayer = HashMap<GuestId, String>()
    private val playerToGuest = HashMap<String, GuestId>()

    var onStateChange: (() -> Unit)? = null
    private var statRecorded = false

    init {
        server.onMessage = ::onMessage
        server.onLeave = ::onLeave
    }

    companion object { const val HOST_ID = "host" }

    fun start(): String? {
        engine.addPlayer(HOST_ID, hostName, isHost = true)
        val url = server.startServer()
        // The host plays as a normal player on the same screen guests see.
        val local = server.attachLocalGuest()
        guestToPlayer[local] = HOST_ID
        playerToGuest[HOST_ID] = local
        emit()
        return url
    }

    /** In-process pipe for the host's own player screen. */
    fun makeLoopback(): LoopbackGuest = LoopbackGuest(server)

    fun stop() { server.stopServer(); resetState() }

    /** Clear all per-session state so the next time the host starts
     *  hosting they get a fresh screen — empty lobby, tutorial vote
     *  available again. */
    private fun resetState() {
        engine = MafiaEngine()
        guestToPlayer.clear(); playerToGuest.clear()
        statRecorded = false
        emit()
    }
    val guestCount: Int get() = server.guestCount

    // Host actions
    fun hostSetOptions(o: MafiaOptions) {
        engine.setOptions(o)
        broadcastOptions(); emit()
    }
    fun hostStart() {
        if (!engine.canStart) return
        engine.start()
        broadcastPhase(); sendRolesPrivately(); emit()
    }
    fun hostNightAction(targetId: String) = applyNightAction(HOST_ID, targetId)
    fun hostDayVote(targetId: String?) = applyDayVote(HOST_ID, targetId)
    fun hostCallTutorialVote() = openTutorialVote()
    fun hostTutorialVote(yes: Boolean) = submitTutorialVote(HOST_ID, yes)
    fun hostDismissTutorial() { engine.tutorialVote.markShown(); broadcastTutorialState(); emit() }
    fun advanceFromReveal() {
        engine.advanceToDayVote()
        if (engine.phase == MafiaPhase.GAME_OVER) broadcastGameOver() else broadcastPhase()
        emit()
    }

    // Inbound
    private fun onMessage(guest: GuestId, raw: String) {
        val j = runCatching { JSONObject(raw) }.getOrNull() ?: return
        when (j.optString("type")) {
            "join" -> handleJoin(guest, j)
            "night_action" -> guestToPlayer[guest]?.let { applyNightAction(it, j.getString("targetId")) }
            "vote" -> guestToPlayer[guest]?.let {
                applyDayVote(it, if (j.isNull("targetId")) null else j.getString("targetId"))
            }
            "chat" -> guestToPlayer[guest]?.let { relayChat(it, j.optString("text")) }
            // Only the host (not connected over WebSocket) may mutate options.
            "set_options" -> Unit
            "call_tutorial_vote" -> guestToPlayer[guest]?.let { openTutorialVote() }
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
        if (engine.phase != MafiaPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already started"))
            return
        }
        val name = j.optString("name").trim().take(24)
        if (name.isEmpty()) return
        val pid = "p${guest.value}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "mafia"))
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private fun broadcastOptions() {
        val o = engine.options
        broadcast(JSONObject()
            .put("type", "options")
            .put("mafiaCount", o.mafiaCount ?: JSONObject.NULL)
            .put("doctorEnabled", o.doctorEnabled)
            .put("maxMafiaCount", engine.maxMafiaCount))
    }

    private fun applyNightAction(playerId: String, targetId: String) {
        val p = engine.players[playerId] ?: return
        if (!p.alive) return
        val ready = when (p.role) {
            MafiaRole.MAFIA -> engine.submitMafiaVote(playerId, targetId)
            MafiaRole.DOCTOR -> engine.submitDoctorTarget(playerId, targetId)
            else -> false
        }
        emit()
        if (ready) { engine.resolveNight(); broadcastNightResult(); emit() }
    }

    private fun applyDayVote(playerId: String, targetId: String?) {
        val ready = engine.submitDayVote(playerId, targetId)
        broadcastVoteUpdate(); emit()
        if (ready) {
            engine.resolveDay()
            broadcastDayResult()
            if (engine.phase == MafiaPhase.GAME_OVER) broadcastGameOver() else broadcastPhase()
            emit()
        }
    }

    /** Relay a private message between mafia team-mates. Only a living mafia
     *  player may speak; every mafia (the whole "must agree" cabal) receives it. */
    private fun relayChat(playerId: String, text: String) {
        val sender = engine.players[playerId] ?: return
        if (sender.role != MafiaRole.MAFIA || !sender.alive) return
        val trimmed = text.trim().take(240)
        if (trimmed.isEmpty()) return
        val payload = JSONObject().put("type", "chat").put("fromId", sender.id)
            .put("fromName", sender.name).put("text", trimmed)
        for (p in engine.players.values) if (p.role == MafiaRole.MAFIA) {
            playerToGuest[p.id]?.let { send(it, payload) }
        }
    }

    // Outbound
    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) {
            arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost))
        }
        broadcast(JSONObject().put("type", "lobby").put("players", arr).put("canStart", engine.canStart))
    }

    private fun sendRolesPrivately() {
        val mafiaIds = JSONArray(engine.players.values.filter { it.role == MafiaRole.MAFIA }.map { it.id })
        for (p in engine.players.values) {
            val payload = JSONObject().put("type", "role").put("role", p.role!!.name.lowercase())
            if (p.role == MafiaRole.MAFIA) payload.put("mafiaIds", mafiaIds)
            playerToGuest[p.id]?.let { send(it, payload) }
        }
    }

    private fun broadcastPhase() {
        broadcast(JSONObject().apply {
            put("type", "phase"); put("phase", phaseJson(engine.phase)); put("day", engine.day)
            put("alive", publicArray(engine.alive)); put("dead", publicArray(engine.dead))
        })
    }
    private fun broadcastVoteUpdate() {
        val votes = JSONObject()
        for ((k, v) in engine.dayVotes) votes.put(k, v ?: "")
        broadcast(JSONObject().put("type", "vote_update").put("votes", votes))
    }
    private fun broadcastNightResult() {
        val n = engine.lastNight!!
        broadcast(JSONObject().apply {
            put("type", "phase"); put("phase", phaseJson(engine.phase)); put("day", engine.day)
            put("alive", publicArray(engine.alive)); put("dead", publicArray(engine.dead))
            put("killedId", n.killedId ?: JSONObject.NULL)
            put("savedId", n.savedId ?: JSONObject.NULL)
        })
    }
    private fun broadcastDayResult() {
        val d = engine.lastDay!!
        val role = d.eliminatedId?.let { engine.players[it]?.role?.name?.lowercase() }
        broadcast(JSONObject().apply {
            put("type", "day_result")
            put("eliminatedId", d.eliminatedId ?: JSONObject.NULL)
            put("tally", JSONObject(d.tally as Map<*, *>))
            put("alive", publicArray(engine.alive)); put("dead", publicArray(engine.dead))
            put("eliminatedRole", role ?: JSONObject.NULL)
        })
    }
    private fun broadcastGameOver() {
        if (!statRecorded) {
            statRecorded = true
            StatsStore.record(
                appCtx, "mafia",
                engine.players.values.map { it.name },
                if (engine.winner == MafiaWinner.TOWN) "town" else "mafia",
            )
        }
        val roles = JSONObject()
        for (p in engine.players.values) roles.put(p.id, p.role!!.name.lowercase())
        broadcast(JSONObject()
            .put("type", "game_over")
            .put("winner", if (engine.winner == MafiaWinner.TOWN) "town" else "mafia")
            .put("roles", roles))
    }

    private fun openTutorialVote() {
        if (engine.phase != MafiaPhase.LOBBY) return
        if (engine.tutorialVote.isOpen || engine.tutorialVote.tutorialShown) return
        engine.tutorialVote.open(engine.players.keys)
        broadcastTutorialState(); emit()
    }
    private fun submitTutorialVote(voterId: String, yes: Boolean) {
        if (!engine.tutorialVote.isOpen) return
        engine.tutorialVote.submit(voterId, yes)
        broadcastTutorialState(); emit()
    }
    private fun broadcastTutorialState() {
        val v = engine.tutorialVote
        val p = JSONObject()
            .put("type", "tutorial_vote_state")
            .put("isOpen", v.isOpen).put("yesCount", v.yesCount).put("noCount", v.noCount)
            .put("eligibleCount", v.eligibleCount)
            .put("result", v.result ?: JSONObject.NULL).put("tutorialShown", v.tutorialShown)
        if (v.result == true && !v.tutorialShown) {
            p.put("title", GameTutorials.mafia.title)
            p.put("sections", JSONArray(GameTutorials.mafia.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.mafia.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun phaseJson(p: MafiaPhase): String = when (p) {
        MafiaPhase.LOBBY -> "lobby"; MafiaPhase.NIGHT -> "night"
        MafiaPhase.DAY_REVEAL -> "dayReveal"; MafiaPhase.DAY_VOTE -> "dayVote"
        MafiaPhase.GAME_OVER -> "gameOver"
    }

    private fun publicArray(ps: List<MafiaPlayer>): JSONArray {
        val arr = JSONArray()
        for (p in ps) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("alive", p.alive))
        return arr
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(obj: JSONObject) = server.broadcast(obj.toString())
    private fun send(guest: GuestId, obj: JSONObject) = server.send(guest, obj.toString())
}
