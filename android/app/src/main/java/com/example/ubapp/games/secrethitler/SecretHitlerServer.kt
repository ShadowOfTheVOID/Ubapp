package com.example.ubapp.games.secrethitler

import android.content.Context
import com.example.ubapp.join.LoopbackGuest
import com.example.ubapp.social.GuestId
import com.example.ubapp.social.HostServer
import com.example.ubapp.stats.StatsStore
import com.example.ubapp.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/**
 * Wraps [HostServer] with Secret-Hitler-specific routing. Mirrors
 * SecretHitlerServer.swift — owns the engine, fans out public state plus
 * per-player private overlays (presidential hand, chancellor hand, peek,
 * investigation), and converts guest commands into engine calls.
 */
class SecretHitlerServer(context: Context, val hostName: String = "Host") {
    val engine = SecretHitlerEngine()
    private val server = HostServer(html = HostServer.htmlAsset(context, "secret_hitler_browser.html"), ctx = context)
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
        val local = server.attachLocalGuest()
        guestToPlayer[local] = HOST_ID
        playerToGuest[HOST_ID] = local
        emit()
        return url
    }

    /** In-process pipe for the host's own player screen. */
    fun makeLoopback(): LoopbackGuest = LoopbackGuest(server)

    fun stop() = server.stopServer()
    val guestCount: Int get() = server.guestCount

    // Host actions
    fun hostStart() {
        if (!engine.canStart) return
        engine.start(); sendRoles(); broadcastState(); emit()
    }
    fun hostNominate(targetId: String) = applyNominate(HOST_ID, targetId)
    fun hostVote(ja: Boolean) = applyVote(HOST_ID, ja)
    fun hostDiscard(index: Int) = applyDiscard(HOST_ID, index)
    fun hostEnact(index: Int) = applyEnact(HOST_ID, index)
    fun hostRequestVeto() = applyRequestVeto(HOST_ID)
    fun hostVetoResponse(confirm: Boolean) = applyVetoResponse(HOST_ID, confirm)
    fun hostAcknowledgePeek() = applyAcknowledgePeek(HOST_ID)
    fun hostInvestigate(targetId: String) = applyInvestigate(HOST_ID, targetId)
    fun hostAcknowledgeInvestigation() = applyAcknowledgeInvestigation(HOST_ID)
    fun hostSpecialElection(targetId: String) = applySpecialElection(HOST_ID, targetId)
    fun hostExecute(targetId: String) = applyExecute(HOST_ID, targetId)
    fun hostCallTutorialVote() = openTutorialVote()
    fun hostTutorialVote(yes: Boolean) = submitTutorialVote(HOST_ID, yes)
    fun hostDismissTutorial() {
        engine.tutorialVote.markShown(); broadcastTutorialState(); emit()
    }

    // Inbound
    private fun onMessage(guest: GuestId, raw: String) {
        val j = runCatching { JSONObject(raw) }.getOrNull() ?: return
        when (j.optString("type")) {
            "join" -> handleJoin(guest, j)
            "nominate" -> guestToPlayer[guest]?.let { applyNominate(it, j.getString("targetId")) }
            "vote" -> guestToPlayer[guest]?.let { applyVote(it, j.getBoolean("ja")) }
            "discard" -> guestToPlayer[guest]?.let { applyDiscard(it, j.getInt("index")) }
            "enact" -> guestToPlayer[guest]?.let { applyEnact(it, j.getInt("index")) }
            "request_veto" -> guestToPlayer[guest]?.let { applyRequestVeto(it) }
            "veto_response" -> guestToPlayer[guest]?.let { applyVetoResponse(it, j.getBoolean("confirm")) }
            "ack_peek" -> guestToPlayer[guest]?.let { applyAcknowledgePeek(it) }
            "investigate" -> guestToPlayer[guest]?.let { applyInvestigate(it, j.getString("targetId")) }
            "ack_investigation" -> guestToPlayer[guest]?.let { applyAcknowledgeInvestigation(it) }
            "special_election" -> guestToPlayer[guest]?.let { applySpecialElection(it, j.getString("targetId")) }
            "execute" -> guestToPlayer[guest]?.let { applyExecute(it, j.getString("targetId")) }
            "call_tutorial_vote" -> openTutorialVote()
            "tutorial_vote" -> guestToPlayer[guest]?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        engine.removePlayer(pid)
        engine.tutorialVote.removeVoter(pid)
        broadcastState()
        if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != SecretHitlerPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already started"))
            return
        }
        val name = j.optString("name").trim()
        if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "secret_hitler"))
        broadcastState(); broadcastTutorialState(); emit()
    }

    // Action plumbing
    private fun applyNominate(playerId: String, targetId: String) {
        if (engine.phase != SecretHitlerPhase.NOMINATION || playerId != engine.presidentId) return
        if (engine.nominateChancellor(targetId)) { broadcastState(); emit() }
    }
    private fun applyVote(voterId: String, ja: Boolean) {
        if (engine.phase != SecretHitlerPhase.ELECTION) return
        val ready = engine.submitVote(voterId, ja)
        broadcastVoteProgress(); emit()
        if (ready) {
            engine.resolveElection()
            broadcastElectionResult()
            if (engine.phase == SecretHitlerPhase.GAME_OVER) broadcastGameOver()
            broadcastState()
            if (engine.phase == SecretHitlerPhase.PRESIDENT_DISCARD) sendPresidentialHand()
            emit()
        }
    }
    private fun applyDiscard(playerId: String, index: Int) {
        if (engine.phase != SecretHitlerPhase.PRESIDENT_DISCARD || playerId != engine.presidentId) return
        if (engine.presidentDiscard(index)) { sendChancellorHand(); broadcastState(); emit() }
    }
    private fun applyEnact(playerId: String, index: Int) {
        if (engine.phase != SecretHitlerPhase.CHANCELLOR_ENACT || playerId != engine.chancellorId) return
        if (engine.chancellorEnact(index)) {
            broadcastPolicyResult()
            if (engine.phase == SecretHitlerPhase.POLICY_PEEK) sendPolicyPeek()
            if (engine.phase == SecretHitlerPhase.INVESTIGATION_REVEAL) sendInvestigationResult()
            if (engine.phase == SecretHitlerPhase.GAME_OVER) broadcastGameOver()
            broadcastState(); emit()
        }
    }
    private fun applyRequestVeto(playerId: String) {
        if (engine.phase != SecretHitlerPhase.CHANCELLOR_ENACT || playerId != engine.chancellorId) return
        if (engine.chancellorRequestVeto()) { broadcastState(); emit() }
    }
    private fun applyVetoResponse(playerId: String, confirm: Boolean) {
        if (engine.phase != SecretHitlerPhase.VETO_DECISION || playerId != engine.presidentId) return
        if (engine.presidentVetoResponse(confirm)) {
            if (confirm) broadcastVetoResult()
            broadcastState(); emit()
        }
    }
    private fun applyAcknowledgePeek(playerId: String) {
        if (engine.phase != SecretHitlerPhase.POLICY_PEEK || playerId != engine.presidentId) return
        if (engine.acknowledgePeek()) { broadcastState(); emit() }
    }
    private fun applyInvestigate(playerId: String, targetId: String) {
        if (engine.phase != SecretHitlerPhase.INVESTIGATION || playerId != engine.presidentId) return
        if (engine.investigate(targetId)) { sendInvestigationResult(); broadcastState(); emit() }
    }
    private fun applyAcknowledgeInvestigation(playerId: String) {
        if (engine.phase != SecretHitlerPhase.INVESTIGATION_REVEAL || playerId != engine.presidentId) return
        if (engine.acknowledgeInvestigation()) { broadcastState(); emit() }
    }
    private fun applySpecialElection(playerId: String, targetId: String) {
        if (engine.phase != SecretHitlerPhase.SPECIAL_ELECTION || playerId != engine.presidentId) return
        if (engine.callSpecialElection(targetId)) { broadcastState(); emit() }
    }
    private fun applyExecute(playerId: String, targetId: String) {
        if (engine.phase != SecretHitlerPhase.EXECUTION || playerId != engine.presidentId) return
        if (engine.executePlayer(targetId)) {
            broadcastExecutionResult()
            if (engine.phase == SecretHitlerPhase.GAME_OVER) broadcastGameOver()
            broadcastState(); emit()
        }
    }

    // Tutorial
    private fun openTutorialVote() {
        if (engine.phase != SecretHitlerPhase.LOBBY) return
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
            p.put("title", GameTutorials.secretHitler.title)
            p.put("sections", JSONArray(GameTutorials.secretHitler.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.secretHitler.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    // Outbound — public state
    private fun publicPlayer(p: SecretHitlerPlayer) =
        JSONObject().put("id", p.id).put("name", p.name).put("alive", p.alive).put("isHost", p.isHost)

    private fun broadcastState() {
        val players = JSONArray()
        for (id in engine.seatOrder) engine.players[id]?.let { players.put(publicPlayer(it)) }
        val eligible = JSONArray().apply {
            if (engine.phase == SecretHitlerPhase.NOMINATION)
                for (p in engine.eligibleChancellorNominees()) put(p.id)
        }
        val investigated = JSONArray().apply { for (id in engine.investigatedIds) put(id) }
        val payload = JSONObject().apply {
            put("type", "state")
            put("phase", engine.phase.wire)
            put("players", players)
            put("presidentId", engine.presidentId ?: JSONObject.NULL)
            put("chancellorNomineeId", engine.chancellorNomineeId ?: JSONObject.NULL)
            put("chancellorId", engine.chancellorId ?: JSONObject.NULL)
            put("liberalPolicies", engine.liberalPolicies)
            put("fascistPolicies", engine.fascistPolicies)
            put("electionTracker", engine.electionTracker)
            put("vetoUnlocked", engine.vetoUnlocked)
            put("vetoRequested", engine.vetoRequested)
            put("drawPileCount", engine.drawPile.size)
            put("discardPileCount", engine.discardPile.size)
            put("canStart", engine.canStart)
            put("eligibleChancellors", eligible)
            put("voteProgress", engine.electionVotes.size)
            put("voteTotal", engine.alive.size)
            put("investigatedIds", investigated)
            engine.lastEnactedPolicy?.let {
                put("lastEnactedPolicy", it.wire)
                put("lastEnactedByChaos", engine.lastEnactedByChaos)
            }
            engine.lastExecutedId?.let { put("lastExecutedId", it) }
        }
        broadcast(payload)
    }

    private fun broadcastVoteProgress() {
        broadcast(JSONObject()
            .put("type", "vote_progress")
            .put("voteProgress", engine.electionVotes.size)
            .put("voteTotal", engine.alive.size))
    }

    private fun broadcastElectionResult() {
        val passed = engine.lastElectionPassed ?: return
        val voteMap = JSONObject()
        for ((k, v) in engine.electionVotes) voteMap.put(k, v)
        broadcast(JSONObject()
            .put("type", "election_result")
            .put("passed", passed)
            .put("votes", voteMap)
            .put("electionTracker", engine.electionTracker))
    }

    private fun broadcastPolicyResult() {
        val last = engine.lastEnactedPolicy ?: return
        broadcast(JSONObject()
            .put("type", "policy_enacted")
            .put("policy", last.wire)
            .put("liberalPolicies", engine.liberalPolicies)
            .put("fascistPolicies", engine.fascistPolicies)
            .put("byChaos", engine.lastEnactedByChaos))
    }

    private fun broadcastVetoResult() {
        broadcast(JSONObject()
            .put("type", "veto_confirmed")
            .put("electionTracker", engine.electionTracker))
    }

    private fun broadcastExecutionResult() {
        val kid = engine.lastExecutedId ?: return
        broadcast(JSONObject().put("type", "executed").put("playerId", kid))
    }

    private fun broadcastGameOver() {
        if (!statRecorded) {
            statRecorded = true
            StatsStore.record(
                appCtx, "secret_hitler",
                engine.players.values.map { it.name },
                engine.winner?.wire ?: "unknown",
            )
        }
        val roles = JSONObject()
        for (p in engine.players.values) p.role?.let { roles.put(p.id, it.wire) }
        broadcast(JSONObject()
            .put("type", "game_over")
            .put("winner", engine.winner?.wire ?: "")
            .put("reason", engine.winReason?.wire ?: "")
            .put("roles", roles))
    }

    // Outbound — private overlays
    private fun sendRoles() {
        for (p in engine.players.values) {
            val role = p.role ?: continue
            val allies = JSONArray()
            for (aid in engine.knownAllies(p.id)) {
                val ap = engine.players[aid] ?: continue
                allies.put(JSONObject()
                    .put("id", ap.id).put("name", ap.name)
                    .put("role", ap.role?.wire ?: ""))
            }
            val payload = JSONObject()
                .put("type", "role")
                .put("role", role.wire)
                .put("allies", allies)
            playerToGuest[p.id]?.let { send(it, payload) }
        }
    }

    private fun sendPresidentialHand() {
        val pid = engine.presidentId ?: return
        val g = playerToGuest[pid] ?: return
        send(g, JSONObject()
            .put("type", "presidential_hand")
            .put("policies", JSONArray(engine.presidentialHand.map { it.wire })))
    }

    private fun sendChancellorHand() {
        val cid = engine.chancellorId ?: return
        val g = playerToGuest[cid] ?: return
        send(g, JSONObject()
            .put("type", "chancellor_hand")
            .put("policies", JSONArray(engine.chancellorHand.map { it.wire }))
            .put("vetoUnlocked", engine.vetoUnlocked))
    }

    private fun sendPolicyPeek() {
        val pid = engine.presidentId ?: return
        val g = playerToGuest[pid] ?: return
        send(g, JSONObject()
            .put("type", "policy_peek")
            .put("policies", JSONArray(engine.peekedPolicies.map { it.wire })))
    }

    private fun sendInvestigationResult() {
        val pid = engine.presidentId ?: return
        val g = playerToGuest[pid] ?: return
        val inv = engine.lastInvestigation ?: return
        send(g, JSONObject()
            .put("type", "investigation_result")
            .put("subjectId", inv.subjectId)
            .put("party", inv.party.wire))
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(obj: JSONObject) = server.broadcast(obj.toString())
    private fun send(guest: GuestId, obj: JSONObject) = server.send(guest, obj.toString())
}
