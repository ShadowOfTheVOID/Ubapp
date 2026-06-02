package com.example.jamboree.games.president

import android.content.Context
import com.example.jamboree.join.LoopbackGuest
import com.example.jamboree.social.GuestId
import com.example.jamboree.social.HostServer
import com.example.jamboree.stats.SeriesScore
import com.example.jamboree.stats.StatsStore
import com.example.jamboree.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

/** Wraps [HostServer] with President (Scum/Asshole) routing. */
class PresidentServer(context: Context, val hostName: String = "Host") {
    var engine = PresidentEngine(); private set
    private val server = HostServer(html = HostServer.htmlAsset(context, "president_browser.html"), ctx = context)
    private val appCtx = context.applicationContext
    private val guestToPlayer = HashMap<GuestId, String>()
    private val playerToGuest = HashMap<String, GuestId>()
    var onStateChange: (() -> Unit)? = null
    private var statRecorded = false
    private val series = SeriesScore()
    // President plays multiple rounds per match (next_round), so the series
    // counts each round's president — gated separately from the once-per-match
    // stat recording.
    private var seriesRecorded = false

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
    fun stop() { server.stopServer(); resetState() }

    /** Clear all per-session state so the next time the host starts
     *  hosting they get a fresh screen — empty lobby, tutorial vote
     *  available again. */
    private fun resetState() {
        engine = PresidentEngine()
        guestToPlayer.clear(); playerToGuest.clear()
        series.reset(); seriesRecorded = false
        statRecorded = false
        emit()
    }
    val guestCount: Int get() = server.guestCount

    fun hostSetOptions(o: PresOptions) {
        engine.setOptions(o); broadcastOptions(); emit()
    }
    fun hostStart() {
        seriesRecorded = false
        engine.start(); broadcastState(); sendHandsPrivately(); broadcastSwapPrompts(); emit()
    }
    fun hostNextRound() {
        seriesRecorded = false
        engine.startNextRound(); broadcastState(); sendHandsPrivately(); broadcastSwapPrompts(); emit()
    }
    fun hostNewGame() {
        engine.reset(); statRecorded = false
        broadcast(JSONObject().put("type", "reset")); broadcastLobby(); broadcastTutorialState()
        if (!series.isEmpty) broadcastSeries()
        emit()
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
            "pass" -> pid?.let { applyPass(it) }
            "swap" -> pid?.let { applySwap(it, j) }
            "next_round" -> if (engine.phase == PresidentPhase.GAME_OVER) hostNextRound()
            "set_options" -> Unit
            "call_tutorial_vote" -> openTutorialVote()
            "tutorial_vote" -> pid?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        if (engine.phase == PresidentPhase.LOBBY) {
            engine.removePlayer(pid); engine.tutorialVote.removeVoter(pid); broadcastLobby()
            if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        }
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != PresidentPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already in progress")); return
        }
        val name = j.optString("name").trim(); if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid; playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "president"))
        broadcastLobby(); broadcastOptions(); broadcastTutorialState()
        if (!series.isEmpty) broadcastSeries()
        emit()
    }

    private fun applyPlay(pid: String, j: JSONObject) {
        val cards = parseCards(j.optJSONArray("cards")) ?: return
        val err = engine.play(pid, cards)
        if (err == null) {
            broadcastState(); sendHandsPrivately()
            if (engine.phase == PresidentPhase.GAME_OVER) broadcastOver()
            emit()
        } else playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
    }

    private fun applyPass(pid: String) {
        val err = engine.pass(pid)
        if (err == null) { broadcastState(); emit() }
        else playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
    }

    private fun applySwap(pid: String, j: JSONObject) {
        val cards = parseCards(j.optJSONArray("cards")) ?: emptyList()
        val err = engine.submitSwap(pid, cards)
        if (err == null) {
            broadcastState(); sendHandsPrivately(); broadcastSwapPrompts(); emit()
        } else playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
    }

    private fun parseCards(arr: JSONArray?): List<PresCard>? {
        if (arr == null) return null
        val out = ArrayList<PresCard>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val suit = PresSuit.entries.firstOrNull { it.name.equals(o.getString("suit"), true) } ?: return null
            out.add(PresCard(suit, o.getInt("rank")))
        }
        return out
    }

    private fun broadcastOptions() {
        broadcast(JSONObject().put("type", "options")
            .put("allowHouseRules", engine.options.allowHouseRules)
            .put("revolution", engine.options.revolution))
    }

    private fun broadcastLobby() {
        val arr = JSONArray()
        for (p in engine.players.values) arr.put(JSONObject().put("id", p.id).put("name", p.name).put("isHost", p.isHost))
        broadcast(JSONObject().put("type", "lobby").put("players", arr))
    }

    private fun broadcastState() {
        val playersArr = JSONArray()
        for (p in engine.players.values) {
            playersArr.put(JSONObject()
                .put("id", p.id).put("name", p.name)
                .put("handCount", p.hand.size)
                .put("rank", p.rank.wireValue())
                .put("finished", p.finished)
                .put("finishOrder", p.finishOrder))
        }
        val phase = when (engine.phase) {
            PresidentPhase.LOBBY -> "lobby"
            PresidentPhase.SWAPPING -> "swapping"
            PresidentPhase.PLAYING -> "playing"
            PresidentPhase.GAME_OVER -> "gameOver"
        }
        val payload = JSONObject()
            .put("type", "state").put("phase", phase)
            .put("currentId", engine.current?.id ?: JSONObject.NULL)
            .put("roundNumber", engine.roundNumber)
            .put("lastEvent", engine.lastEvent ?: "")
            .put("players", playersArr)
            .put("seating", JSONArray(engine.seatingSnapshot))
            .put("passedThisTrick", JSONArray(engine.passedThisTrick.toList()))
        engine.trick?.let { t ->
            val obj = comboJson(t.combo).put("topPower", t.topPower).put("leaderId", t.leaderId)
            payload.put("trick", obj)
        }
        engine.lastPlay?.let { lp ->
            val cards = JSONArray()
            for (c in lp.cards) cards.put(JSONObject().put("suit", c.suit.name.lowercase()).put("rank", c.rank))
            payload.put("lastPlay", JSONObject()
                .put("playerId", lp.playerId)
                .put("cards", cards)
                .put("combo", comboJson(lp.combo)))
        }
        broadcast(payload)
    }

    private fun comboJson(c: PresCombo): JSONObject = when (c) {
        is PresCombo.Single -> JSONObject().put("kind", "single").put("length", 1)
        is PresCombo.Pair -> JSONObject().put("kind", "pair").put("length", 2)
        is PresCombo.Triple -> JSONObject().put("kind", "triple").put("length", 3)
        is PresCombo.Quad -> JSONObject().put("kind", "quad").put("length", 4)
        is PresCombo.RunOfPairs -> JSONObject().put("kind", "runOfPairs").put("length", c.length * 2)
    }

    private fun sendHandsPrivately() {
        for (p in engine.players.values) {
            val g = playerToGuest[p.id] ?: continue
            val cards = JSONArray()
            for (c in p.hand) cards.put(JSONObject().put("suit", c.suit.name.lowercase()).put("rank", c.rank))
            send(g, JSONObject().put("type", "hand").put("cards", cards))
        }
    }

    private fun broadcastSwapPrompts() {
        for (p in engine.players.values) {
            val g = playerToGuest[p.id] ?: continue
            val arr = JSONArray()
            for (sw in engine.pendingSwaps) {
                if (sw.cards != null || sw.fromId != p.id) continue
                arr.put(JSONObject()
                    .put("toId", sw.toId)
                    .put("toName", engine.players[sw.toId]?.name ?: "")
                    .put("count", sw.count)
                    .put("giverChooses", sw.giverChooses))
            }
            send(g, JSONObject().put("type", "swap_prompts").put("prompts", arr))
        }
    }

    private fun broadcastOver() {
        if (!statRecorded) {
            statRecorded = true
            val names = ArrayList<String>()
            for (pid in engine.finishOrder) engine.players[pid]?.let { names.add(it.name) }
            StatsStore.record(appCtx, "president", names, "win")
        }
        if (!seriesRecorded) {
            seriesRecorded = true
            val presidentName = engine.finishOrder.firstOrNull()?.let { engine.players[it]?.name }
            if (presidentName != null) { series.record(presidentName); broadcastSeries() }
        }
        val rankings = JSONArray()
        for (pid in engine.finishOrder) {
            val p = engine.players[pid] ?: continue
            rankings.put(JSONObject()
                .put("id", p.id).put("name", p.name)
                .put("rank", p.rank.wireValue())
                .put("finishOrder", p.finishOrder))
        }
        broadcast(JSONObject().put("type", "over").put("rankings", rankings))
    }

    private fun openTutorialVote() {
        if (engine.phase != PresidentPhase.LOBBY) return
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
            p.put("title", GameTutorials.president.title)
            p.put("sections", JSONArray(GameTutorials.president.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.president.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
        }
        broadcast(p)
    }

    private fun broadcastSeries() {
        val scores = JSONObject()
        for ((k, v) in series.scores) scores.put(k, v)
        broadcast(JSONObject().put("type", "series_state").put("rounds", series.rounds).put("scores", scores))
    }

    private fun emit() { onStateChange?.invoke() }
    private fun broadcast(o: JSONObject) = server.broadcast(o.toString())
    private fun send(g: GuestId, o: JSONObject) = server.send(g, o.toString())
}
