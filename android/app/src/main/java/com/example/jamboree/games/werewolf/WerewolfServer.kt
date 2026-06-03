package com.example.jamboree.games.werewolf

import android.content.Context
import com.example.jamboree.join.LoopbackGuest
import com.example.jamboree.social.GuestId
import com.example.jamboree.social.HostServer
import com.example.jamboree.stats.StatsStore
import com.example.jamboree.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/** Wraps [HostServer] with Werewolf-specific routing. */
class WerewolfServer(context: Context, val hostName: String = "Host") {
    var engine = WerewolfEngine(); private set
    private val server = HostServer(html = HostServer.htmlAsset(context, "werewolf_browser.html"), ctx = context)
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

    /** In-process pipe for the host's own player screen. */
    fun makeLoopback(): LoopbackGuest = LoopbackGuest(server)

    fun stop() { server.stopServer(); resetState() }

    /** Clear all per-session state so the next time the host starts
     *  hosting they get a fresh screen — empty lobby, tutorial vote
     *  available again. */
    private fun resetState() {
        engine = WerewolfEngine()
        guestToPlayer.clear(); playerToGuest.clear()
        statRecorded = false
        emit()
    }
    val guestCount: Int get() = server.guestCount

    fun hostSetOptions(o: WerewolfOptions) {
        engine.setOptions(o); broadcastOptions(); emit()
    }
    fun hostStart() { if (!engine.canStart) return; engine.start(); broadcastPhase(); sendRolesPrivately(); emit() }
    fun hostNightAction(targetId: String) = applyNightAction(HOST_ID, targetId)
    fun hostDayVote(targetId: String?) = applyDayVote(HOST_ID, targetId)
    fun hostHunterShot(targetId: String) = applyHunterShot(HOST_ID, targetId)
    fun hostCallTutorialVote() = openTutorialVote()
    fun hostTutorialVote(yes: Boolean) = submitTutorialVote(HOST_ID, yes)
    fun hostDismissTutorial() { engine.tutorialVote.markShown(); broadcastTutorialState(); emit() }
    fun advanceFromReveal() {
        engine.advanceToDayVote()
        if (engine.phase == WerewolfPhase.GAME_OVER) broadcastGameOver() else broadcastPhase()
        emit()
    }

    private fun onMessage(guest: GuestId, raw: String) {
        val j = runCatching { JSONObject(raw) }.getOrNull() ?: return
        when (j.optString("type")) {
            "join" -> handleJoin(guest, j)
            "night_action" -> guestToPlayer[guest]?.let { applyNightAction(it, j.getString("targetId")) }
            "vote" -> guestToPlayer[guest]?.let {
                applyDayVote(it, if (j.isNull("targetId")) null else j.getString("targetId"))
            }
            "hunter_shot" -> guestToPlayer[guest]?.let { applyHunterShot(it, j.getString("targetId")) }
            // Only the host (not over WebSocket) may mutate options.
            "set_options" -> Unit
            "call_tutorial_vote" -> guestToPlayer[guest]?.let { openTutorialVote() }
            "tutorial_vote" -> guestToPlayer[guest]?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        engine.removePlayer(pid); engine.tutorialVote.removeVoter(pid)
        broadcastLobby()
        if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != WerewolfPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already started")); return
        }
        val name = j.optString("name").trim().take(24); if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid; playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "werewolf"))
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private fun broadcastOptions() {
        val o = engine.options
        broadcast(JSONObject()
            .put("type", "options")
            .put("wolfCount", o.wolfCount ?: JSONObject.NULL)
            .put("seerEnabled", o.seerEnabled)
            .put("hunterEnabled", o.hunterEnabled)
            .put("maxWolfCount", engine.maxWolfCount))
    }

    private fun applyNightAction(playerId: String, targetId: String) {
        val p = engine.players[playerId] ?: return
        if (!p.alive) return
        val ready = when (p.role) {
            WerewolfRole.WEREWOLF -> engine.submitWolfVote(playerId, targetId)
            WerewolfRole.SEER -> engine.submitSeerTarget(playerId, targetId)
            else -> false
        }
        emit()
        if (ready) {
            engine.resolveNight(); sendSeerResultPrivately(); broadcastNightResult()
            if (engine.phase == WerewolfPhase.GAME_OVER) broadcastGameOver()
            else if (engine.phase == WerewolfPhase.HUNTER_SHOT) broadcastHunterPrompt()
            emit()
        }
    }

    private fun applyDayVote(playerId: String, targetId: String?) {
        val ready = engine.submitDayVote(playerId, targetId); broadcastVoteUpdate(); emit()
        if (ready) {
            engine.resolveDay(); broadcastDayResult()
            if (engine.phase == WerewolfPhase.GAME_OVER) broadcastGameOver()
            else if (engine.phase == WerewolfPhase.HUNTER_SHOT) broadcastHunterPrompt()
            else broadcastPhase()
            emit()
        }
    }

    private fun applyHunterShot(playerId: String, targetId: String) {
        if (!engine.submitHunterShot(playerId, targetId)) return
        broadcastHunterShotResult()
        if (engine.phase == WerewolfPhase.GAME_OVER) broadcastGameOver()
        else if (engine.phase == WerewolfPhase.HUNTER_SHOT) broadcastHunterPrompt()
        else broadcastPhase()
        emit()
    }

    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost))
        broadcast(JSONObject().put("type", "lobby").put("players", arr).put("canStart", engine.canStart))
    }
    private fun sendRolesPrivately() {
        val wolfIds = JSONArray(engine.players.values.filter { it.role == WerewolfRole.WEREWOLF }.map { it.id })
        for (p in engine.players.values) {
            val payload = JSONObject().put("type", "role").put("role", roleName(p.role!!))
            if (p.role == WerewolfRole.WEREWOLF) payload.put("wolfIds", wolfIds)
            playerToGuest[p.id]?.let { send(it, payload) }
        }
    }
    private fun sendSeerResultPrivately() {
        val r = engine.lastSeerResult ?: return
        val guest = playerToGuest[r.seerId] ?: return
        send(guest, JSONObject().put("type", "seer_result").put("targetId", r.targetId).put("isWerewolf", r.isWerewolf))
    }
    private fun broadcastPhase() {
        broadcast(JSONObject()
            .put("type", "phase").put("phase", phaseJson(engine.phase)).put("day", engine.day)
            .put("alive", publicArr(engine.alive)).put("dead", publicArr(engine.dead)))
    }
    private fun broadcastVoteUpdate() {
        val votes = JSONObject(); for ((k, v) in engine.dayVotes) votes.put(k, v ?: "")
        broadcast(JSONObject().put("type", "vote_update").put("votes", votes))
    }
    private fun broadcastNightResult() {
        val n = engine.lastNight!!
        broadcast(JSONObject()
            .put("type", "phase").put("phase", phaseJson(engine.phase)).put("day", engine.day)
            .put("alive", publicArr(engine.alive)).put("dead", publicArr(engine.dead))
            .put("killedId", n.killedId ?: JSONObject.NULL))
    }
    private fun broadcastDayResult() {
        val d = engine.lastDay!!
        val role = d.eliminatedId?.let { engine.players[it]?.role?.let { r -> roleName(r) } }
        broadcast(JSONObject()
            .put("type", "day_result")
            .put("eliminatedId", d.eliminatedId ?: JSONObject.NULL)
            .put("tally", JSONObject(d.tally as Map<*, *>))
            .put("alive", publicArr(engine.alive)).put("dead", publicArr(engine.dead))
            .put("eliminatedRole", role ?: JSONObject.NULL))
    }
    private fun broadcastHunterPrompt() {
        broadcast(JSONObject()
            .put("type", "hunter_prompt")
            .put("hunterId", engine.pendingHunterShooter ?: JSONObject.NULL)
            .put("alive", publicArr(engine.alive)).put("dead", publicArr(engine.dead)))
    }
    private fun broadcastHunterShotResult() {
        val last = engine.hunterShotsThisRound.lastOrNull() ?: return
        broadcast(JSONObject()
            .put("type", "hunter_shot_result")
            .put("hunterId", last.hunterId).put("targetId", last.targetId)
            .put("targetRole", roleName(engine.players[last.targetId]!!.role!!))
            .put("alive", publicArr(engine.alive)).put("dead", publicArr(engine.dead)))
    }
    private fun broadcastGameOver() {
        if (!statRecorded) {
            statRecorded = true
            StatsStore.record(
                appCtx, "werewolf",
                engine.players.values.map { it.name },
                if (engine.winner == WerewolfWinner.TOWN) "town" else "werewolves",
            )
        }
        val roles = JSONObject()
        for (p in engine.players.values) roles.put(p.id, roleName(p.role!!))
        broadcast(JSONObject().put("type", "game_over")
            .put("winner", if (engine.winner == WerewolfWinner.TOWN) "town" else "werewolves")
            .put("roles", roles))
    }

    private fun openTutorialVote() {
        if (engine.phase != WerewolfPhase.LOBBY) return
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
            p.put("title", GameTutorials.werewolf.title)
            p.put("sections", JSONArray(GameTutorials.werewolf.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.werewolf.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun phaseJson(p: WerewolfPhase) = when (p) {
        WerewolfPhase.LOBBY -> "lobby"; WerewolfPhase.NIGHT -> "night"
        WerewolfPhase.DAY_REVEAL -> "dayReveal"; WerewolfPhase.DAY_VOTE -> "dayVote"
        WerewolfPhase.HUNTER_SHOT -> "hunterShot"; WerewolfPhase.GAME_OVER -> "gameOver"
    }
    private fun roleName(r: WerewolfRole) = r.name.lowercase()

    private fun publicArr(ps: List<WerewolfPlayer>): JSONArray {
        val a = JSONArray()
        for (p in ps) a.put(JSONObject().put("id", p.id).put("name", p.name).put("alive", p.alive))
        return a
    }
    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(o: JSONObject) = server.broadcast(o.toString())
    private fun send(g: GuestId, o: JSONObject) = server.send(g, o.toString())
}
