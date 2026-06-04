package com.example.jamboree.games.bureaucrat

import android.content.Context
import com.example.jamboree.join.LoopbackGuest
import com.example.jamboree.social.GuestId
import com.example.jamboree.social.HostServer
import com.example.jamboree.stats.StatsStore
import com.example.jamboree.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Wraps [HostServer] with The Bureaucrat's routing. Owns the engine, the
 * rebuttal countdown (the one piece of real I/O the pure engine refuses to
 * touch), and the [ContradictionDetector] used to judge rebuttals. Mirrors
 * the structure of [com.example.jamboree.games.mafia.MafiaServer].
 */
class BureaucratServer(context: Context, val hostName: String = "Host") {
    var engine = BureaucratEngine(); private set
    private val server = HostServer(html = HostServer.htmlAsset(context, "bureaucrat_browser.html"), ctx = context)
    private val appCtx = context.applicationContext
    private val guestToPlayer = HashMap<GuestId, String>()
    private val playerToGuest = HashMap<String, GuestId>()

    /** NLI model when its assets are bundled, else the offline keyword check. */
    private val detector: ContradictionDetector =
        OnnxContradictionDetector.tryCreate(context) ?: KeywordContradictionDetector()

    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private var rebuttalTimer: ScheduledFuture<*>? = null
    /** Epoch-ms deadline broadcast so every client renders the same countdown. */
    private var rebuttalDeadline: Long = 0

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

    fun makeLoopback(): LoopbackGuest = LoopbackGuest(server)

    fun stop() {
        cancelTimer()
        scheduler.shutdownNow()
        (detector as? OnnxContradictionDetector)?.close()
        server.stopServer()
        resetState()
    }

    /** Clear all per-session state so the next time the host starts
     *  hosting they get a fresh screen — empty lobby, tutorial vote
     *  available again. */
    private fun resetState() {
        engine = BureaucratEngine()
        guestToPlayer.clear(); playerToGuest.clear()
        rebuttalDeadline = 0
        statRecorded = false
        emit()
    }

    val guestCount: Int get() = server.guestCount

    // Host orchestration (driven from the control bar / loopback host).
    fun hostSetOptions(o: BureaucratOptions) { engine.setOptions(o); broadcastOptions(); emit() }
    fun hostStart() {
        if (!engine.canStart) return
        engine.start(); broadcastRound(); emit()
    }
    fun hostSurvive() {
        if (engine.bureaucratSurvives()) { cancelTimer(); broadcastRoundOver(); emit() }
    }
    fun hostNextRound() {
        if (engine.nextRound()) {
            if (engine.phase == BureaucratPhase.GAME_OVER) broadcastGameOver() else broadcastRound()
            emit()
        }
    }
    fun hostCallTutorialVote() = openTutorialVote()
    fun hostTutorialVote(yes: Boolean) = submitTutorialVote(HOST_ID, yes)
    fun hostDismissTutorial() { engine.tutorialVote.markShown(); broadcastTutorialState(); emit() }

    // Inbound guest commands.
    private fun onMessage(guest: GuestId, raw: String) {
        val j = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val pid = guestToPlayer[guest]
        when (j.optString("type")) {
            "join" -> handleJoin(guest, j)
            "denial" -> pid?.let { applyDenial(it, j.optString("text").take(280)) }
            "call_loophole" -> pid?.let { applyLoophole(it) }
            "rebuttal" -> pid?.let { applyRebuttal(it, j.optString("text").take(280)) }
            "call_tutorial_vote" -> guestToPlayer[guest]?.let { openTutorialVote() }
            "tutorial_vote" -> pid?.let { submitTutorialVote(it, j.getBoolean("yes")) }
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
        if (engine.phase != BureaucratPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already started"))
            return
        }
        val name = j.optString("name").trim().take(24)
        if (name.isEmpty()) return
        val pid = "p${guest.value}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid
        playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "bureaucrat"))
        broadcastLobby(); broadcastOptions(); broadcastTutorialState(); emit()
    }

    private fun applyDenial(playerId: String, text: String) {
        if (engine.addDenial(playerId, text)) { broadcastPolicy(); emit() }
    }

    private fun applyLoophole(citizenId: String) {
        if (engine.callLoophole(citizenId)) {
            rebuttalDeadline = System.currentTimeMillis() + engine.options.rebuttalSeconds * 1000L
            broadcastRebuttalOpen()
            startTimer()
            emit()
        }
    }

    private fun applyRebuttal(playerId: String, text: String) {
        if (engine.phase != BureaucratPhase.REBUTTAL) return
        if (playerId != engine.bureaucratId) return
        if (text.isBlank()) return
        cancelTimer()
        val contradicts = engine.options.aiAssist &&
            detector.contradicts(engine.policyLog.map { it.text }, text)
        if (engine.submitRebuttal(text, contradicts)) {
            if (engine.phase == BureaucratPhase.ROUND_OVER) broadcastRoundOver()
            else broadcastPolicy()   // successful defence: back to arguing
            emit()
        }
    }

    private fun startTimer() {
        cancelTimer()
        rebuttalTimer = scheduler.schedule({
            if (engine.rebuttalTimedOut()) { broadcastRoundOver(); emit() }
        }, engine.options.rebuttalSeconds.toLong(), TimeUnit.SECONDS)
    }
    private fun cancelTimer() { rebuttalTimer?.cancel(false); rebuttalTimer = null }

    // Outbound.
    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) {
            arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost))
        }
        broadcast(JSONObject().put("type", "lobby").put("players", arr).put("canStart", engine.canStart))
    }

    private fun broadcastOptions() {
        val o = engine.options
        broadcast(JSONObject().put("type", "options")
            .put("targetScore", o.targetScore).put("challengeTokens", o.challengeTokens)
            .put("rebuttalSeconds", o.rebuttalSeconds).put("aiAssist", o.aiAssist)
            .put("rebuttalMode", o.rebuttalMode))
    }

    private fun roundCore(j: JSONObject): JSONObject = j.apply {
        put("phase", phaseJson(engine.phase))
        put("roundNumber", engine.roundNumber)
        put("bureaucratId", engine.bureaucratId ?: JSONObject.NULL)
        put("bureaucratName", engine.bureaucratId?.let { engine.players[it]?.name } ?: JSONObject.NULL)
        put("task", engine.task ?: JSONObject.NULL)
        put("targetScore", engine.options.targetScore)
        put("scores", scoresJson())
        put("tokens", tokensJson())
        put("policyLog", policyJson())
    }

    private fun broadcastRound() = broadcast(roundCore(JSONObject().put("type", "round")))
    private fun broadcastPolicy() = broadcast(roundCore(JSONObject().put("type", "policy")))

    private fun broadcastRebuttalOpen() {
        val cid = engine.pendingChallenger
        broadcast(JSONObject().put("type", "rebuttal_open")
            .put("challengerId", cid ?: JSONObject.NULL)
            .put("challengerName", cid?.let { engine.players[it]?.name } ?: JSONObject.NULL)
            .put("seconds", engine.options.rebuttalSeconds)
            .put("deadlineMs", rebuttalDeadline)
            .put("policyLog", policyJson()))
    }

    private fun broadcastRoundOver() {
        val r = engine.lastRound!!
        broadcast(JSONObject().put("type", "round_over")
            .put("bureaucratId", r.bureaucratId)
            .put("bureaucratName", engine.players[r.bureaucratId]?.name ?: r.bureaucratId)
            .put("challengerId", r.challengerId ?: JSONObject.NULL)
            .put("challengerName", r.challengerId?.let { engine.players[it]?.name } ?: JSONObject.NULL)
            .put("reason", reasonJson(r.reason))
            .put("task", r.task)
            .put("nextBureaucratId", engine.nextBureaucratId() ?: JSONObject.NULL)
            .put("scores", scoresJson()).put("targetScore", engine.options.targetScore)
            .put("policyLog", policyJson()))
    }

    private fun broadcastGameOver() {
        if (!statRecorded) {
            statRecorded = true
            StatsStore.record(appCtx, "bureaucrat",
                engine.players.values.map { it.name },
                engine.players[engine.winnerId]?.name ?: "?")
        }
        broadcast(JSONObject().put("type", "game_over")
            .put("winnerId", engine.winnerId ?: JSONObject.NULL)
            .put("winnerName", engine.players[engine.winnerId]?.name ?: JSONObject.NULL)
            .put("scores", scoresJson()))
    }

    private fun scoresJson(): JSONObject {
        val o = JSONObject(); for (p in engine.players.values) o.put(p.id, p.score); return o
    }
    private fun tokensJson(): JSONObject {
        val o = JSONObject(); for (c in engine.citizens) o.put(c.id, engine.tokensFor(c.id)); return o
    }
    private fun policyJson(): JSONArray {
        val arr = JSONArray()
        for (e in engine.policyLog) {
            arr.put(JSONObject().put("text", e.text).put("isRebuttal", e.isRebuttal)
                .put("challengerId", e.challengerId ?: JSONObject.NULL))
        }
        return arr
    }

    private fun openTutorialVote() {
        if (engine.phase != BureaucratPhase.LOBBY) return
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
        val p = JSONObject().put("type", "tutorial_vote_state")
            .put("isOpen", v.isOpen).put("yesCount", v.yesCount).put("noCount", v.noCount)
            .put("eligibleCount", v.eligibleCount)
            .put("result", v.result ?: JSONObject.NULL).put("tutorialShown", v.tutorialShown)
        if (v.result == true && !v.tutorialShown) {
            p.put("title", GameTutorials.bureaucrat.title)
            p.put("sections", JSONArray(GameTutorials.bureaucrat.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.bureaucrat.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun phaseJson(p: BureaucratPhase): String = when (p) {
        BureaucratPhase.LOBBY -> "lobby"; BureaucratPhase.ARGUING -> "arguing"
        BureaucratPhase.REBUTTAL -> "rebuttal"; BureaucratPhase.ROUND_OVER -> "roundOver"
        BureaucratPhase.GAME_OVER -> "gameOver"
    }
    private fun reasonJson(r: RoundEndReason): String = when (r) {
        RoundEndReason.LOOPHOLE_TIMEOUT -> "timeout"
        RoundEndReason.LOOPHOLE_CONTRADICTION -> "contradiction"
        RoundEndReason.BUREAUCRAT_SURVIVED -> "survived"
        RoundEndReason.TOKENS_EXHAUSTED -> "exhausted"
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(obj: JSONObject) = server.broadcast(obj.toString())
    private fun send(guest: GuestId, obj: JSONObject) = server.send(guest, obj.toString())
}
