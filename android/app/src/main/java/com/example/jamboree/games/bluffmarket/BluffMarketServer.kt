package com.example.ubapp.games.bluffmarket

import android.content.Context
import com.example.ubapp.join.LoopbackGuest
import com.example.ubapp.social.GuestId
import com.example.ubapp.social.HostServer
import com.example.ubapp.stats.SeriesScore
import com.example.ubapp.stats.StatsStore
import com.example.ubapp.tutorials.GameTutorials
import org.json.JSONArray
import org.json.JSONObject

class BluffMarketServer(context: Context, val hostName: String = "Host") {
    val engine = BluffMarketEngine()
    private val server = HostServer(html = HostServer.htmlAsset(context, "bluff_market_browser.html"), ctx = context)
    private val appCtx = context.applicationContext
    private val guestToPlayer = HashMap<GuestId, String>()
    private val playerToGuest = HashMap<String, GuestId>()
    var onStateChange: (() -> Unit)? = null
    private var statRecorded = false
    private val series = SeriesScore()

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

    fun hostSetOptions(o: BluffMarketOptions) {
        engine.setOptions(o); broadcastOptions(); emit()
    }
    fun hostStart() { engine.start(); broadcastState(); sendHandsPrivately(); emit() }
    fun hostNewGame() {
        engine.reset(); statRecorded = false
        broadcast(JSONObject().put("type", "reset")); broadcastLobby(); broadcastTutorialState()
        if (!series.isEmpty) broadcastSeries()
        emit()
    }
    fun hostFinalize() { engine.finalize(); broadcastState(); broadcastOver(); emit() }
    fun hostCallTutorialVote() = openTutorialVote()
    fun hostTutorialVote(yes: Boolean) = submitTutorialVote(HOST_ID, yes)
    fun hostDismissTutorial() { engine.tutorialVote.markShown(); broadcastTutorialState(); emit() }

    private fun onMessage(guest: GuestId, raw: String) {
        val j = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val pid = guestToPlayer[guest]
        when (j.optString("type")) {
            "join" -> handleJoin(guest, j)
            "buy" -> pid?.let { applyResult(it, engine.buyFromMarket(it)) }
            "sell" -> pid?.let { applyResult(it, engine.sellToMarket(it, j.optString("cardId"))) }
            "propose_trade" -> pid?.let {
                applyResult(it, engine.proposeTrade(it, j.optString("targetId"), j.optString("cardId")))
            }
            "counter_trade" -> pid?.let {
                applyResult(it, engine.counterTrade(it, j.optString("cardId")))
            }
            "decline_trade" -> pid?.let { applyResult(it, engine.declineTrade(it)) }
            "guarantee" -> pid?.let { applyResult(it, engine.useGuarantee(it)) }
            "respond_trade" -> pid?.let {
                applyResult(it, engine.respondTrade(it, j.optBoolean("accept")))
            }
            "finalize" -> if (engine.phase == BluffMarketPhase.SCORING) hostFinalize()
            "set_options" -> Unit
            "call_tutorial_vote" -> openTutorialVote()
            "tutorial_vote" -> pid?.let { submitTutorialVote(it, j.getBoolean("yes")) }
        }
    }

    private fun applyResult(pid: String, err: String?) {
        if (err == null) {
            broadcastState(); sendHandsPrivately()
            if (engine.phase == BluffMarketPhase.SCORING) broadcastScores()
            if (engine.phase == BluffMarketPhase.GAME_OVER) broadcastOver()
            emit()
        } else playerToGuest[pid]?.let { send(it, JSONObject().put("type", "error").put("message", err)) }
    }

    private fun onLeave(guest: GuestId) {
        val pid = guestToPlayer.remove(guest) ?: return
        playerToGuest.remove(pid)
        if (engine.phase == BluffMarketPhase.LOBBY) {
            engine.removePlayer(pid); engine.tutorialVote.removeVoter(pid); broadcastLobby()
            if (engine.tutorialVote.isOpen || engine.tutorialVote.hasResult) broadcastTutorialState()
        }
        emit()
    }

    private fun handleJoin(guest: GuestId, j: JSONObject) {
        if (engine.phase != BluffMarketPhase.LOBBY) {
            send(guest, JSONObject().put("type", "error").put("message", "Game already in progress")); return
        }
        val name = j.optString("name").trim(); if (name.isEmpty()) return
        val pid = "g${guestToPlayer.size + 1}"
        engine.addPlayer(pid, name)
        guestToPlayer[guest] = pid; playerToGuest[pid] = guest
        send(guest, JSONObject().put("type", "welcome").put("yourId", pid).put("yourName", name).put("game", "bluff_market"))
        broadcastLobby(); broadcastOptions(); broadcastTutorialState()
        if (!series.isEmpty) broadcastSeries()
        emit()
    }

    private fun broadcastOptions() {
        broadcast(JSONObject().put("type", "options")
            .put("turnsPerPlayer", engine.options.turnsPerPlayer)
            .put("twoBombs", engine.options.twoBombs)
            .put("wildcard", engine.options.wildcard))
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
                .put("coins", p.coins)
                .put("turnsTaken", p.turnsTaken)
                .put("guaranteeUsed", p.guaranteeUsed))
        }
        val phase = when (engine.phase) {
            BluffMarketPhase.LOBBY -> "lobby"
            BluffMarketPhase.PLAYING -> "playing"
            BluffMarketPhase.SCORING -> "scoring"
            BluffMarketPhase.GAME_OVER -> "gameOver"
        }
        val payload = JSONObject()
            .put("type", "state")
            .put("phase", phase)
            .put("currentId", engine.current?.id ?: JSONObject.NULL)
            .put("marketSize", engine.market.size)
            .put("lastEvent", engine.lastEvent ?: "")
            .put("players", playersArr)
            .put("turnsPerPlayer", engine.options.turnsPerPlayer)
        engine.activeTrade?.let { t ->
            val tjson = JSONObject()
                .put("proposerId", t.proposerId)
                .put("targetId", t.targetId)
                .put("proposerCommitted", t.proposerCardId != null)
                .put("targetCommitted", t.targetCardId != null)
                .put("revealed", t.revealed)
                .put("proposerGuarantee", t.proposerGuarantee)
                .put("targetGuarantee", t.targetGuarantee)
            t.proposerAccept?.let { tjson.put("proposerAccept", it) }
            t.targetAccept?.let { tjson.put("targetAccept", it) }
            if (t.revealed) {
                t.proposerCardId?.let { engine.cardCatalog[it]?.let { c -> tjson.put("proposerCard", cardJson(c)) } }
                t.targetCardId?.let { engine.cardCatalog[it]?.let { c -> tjson.put("targetCard", cardJson(c)) } }
            }
            payload.put("trade", tjson)
        }
        broadcast(payload)
    }

    private fun cardJson(c: BluffCard): JSONObject {
        val (kind, value) = when (val k = c.kind) {
            is BluffKind.Points -> "points" to k.value
            is BluffKind.Bomb -> "bomb" to k.value
            is BluffKind.Wildcard -> "wildcard" to 0
        }
        return JSONObject()
            .put("id", c.id).put("kind", kind)
            .put("value", value).put("label", c.label)
    }

    private fun sendHandsPrivately() {
        for (p in engine.players.values) {
            val g = playerToGuest[p.id] ?: continue
            val cards = JSONArray()
            for (c in p.hand) cards.put(cardJson(c))
            send(g, JSONObject().put("type", "hand").put("cards", cards))
        }
    }

    private fun broadcastScores() {
        val arr = JSONArray()
        for (r in engine.score()) {
            arr.put(JSONObject()
                .put("id", r.id).put("name", r.name)
                .put("total", r.total).put("sum", r.sum)
                .put("coins", r.coins).put("hasBomb", r.hasBomb))
        }
        broadcast(JSONObject().put("type", "scores").put("rows", arr))
    }

    private fun broadcastOver() {
        val rows = engine.score()
        val winner = rows.maxByOrNull { it.total }
        if (!statRecorded) {
            statRecorded = true
            val names = ArrayList<String>()
            winner?.let { names.add(it.name) }
            for (r in rows) if (r.id != winner?.id) names.add(r.name)
            StatsStore.record(appCtx, "bluff_market", names, "win")
            winner?.let { series.record(it.name); broadcastSeries() }
        }
        val arr = JSONArray()
        for (r in rows) {
            arr.put(JSONObject()
                .put("id", r.id).put("name", r.name)
                .put("total", r.total).put("sum", r.sum)
                .put("coins", r.coins).put("hasBomb", r.hasBomb))
        }
        broadcast(JSONObject().put("type", "over")
            .put("winnerId", winner?.id ?: JSONObject.NULL)
            .put("rows", arr))
    }

    private fun openTutorialVote() {
        if (engine.phase != BluffMarketPhase.LOBBY) return
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
            p.put("title", GameTutorials.bluffMarket.title)
            p.put("sections", JSONArray(GameTutorials.bluffMarket.sectionsJson().map { JSONObject(it as Map<*, *>) }))
            p.put("menuSections", JSONArray(GameTutorials.bluffMarket.browserMenuSectionsJson().map { JSONObject(it as Map<*, *>) }))
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
