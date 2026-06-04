package com.example.jamboree.games.bluffmarket

import kotlin.random.Random

enum class BluffMarketPhase { LOBBY, PLAYING, SCORING, GAME_OVER }

/** Card kind. Bomb's value is negative; wildcard scores 0 (variant: doubles). */
sealed class BluffKind {
    data class Points(val value: Int) : BluffKind()
    data class Bomb(val value: Int) : BluffKind()
    object Wildcard : BluffKind()
}

data class BluffCard(val id: String, val kind: BluffKind) {
    val points: Int get() = when (val k = kind) {
        is BluffKind.Points -> k.value
        is BluffKind.Bomb -> k.value
        is BluffKind.Wildcard -> 0
    }
    val label: String get() = when (val k = kind) {
        is BluffKind.Points -> "+${k.value}"
        is BluffKind.Bomb -> "BOMB"
        is BluffKind.Wildcard -> "WILD"
    }
}

data class BluffMarketOptions(
    val turnsPerPlayer: Int = 5,
    val twoBombs: Boolean = false,
    val wildcard: Boolean = false,
)

class BluffTrade(val proposerId: String, val targetId: String) {
    var proposerCardId: String? = null
    var targetCardId: String? = null
    var proposerGuarantee: Boolean = false
    var targetGuarantee: Boolean = false
    var proposerAccept: Boolean? = null
    var targetAccept: Boolean? = null
    val revealed: Boolean get() = proposerCardId != null && targetCardId != null
}

class BluffPlayer(val id: String, val name: String, val isHost: Boolean) {
    val hand: MutableList<BluffCard> = mutableListOf()
    var coins: Int = 0
    var turnsTaken: Int = 0
    var guaranteeUsed: Boolean = false
}

class BluffMarketEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.jamboree.tutorials.TutorialVote()
    val players: MutableMap<String, BluffPlayer> = linkedMapOf()
    private val seating: MutableList<String> = mutableListOf()
    val seatingSnapshot: List<String> get() = seating.toList()
    var phase: BluffMarketPhase = BluffMarketPhase.LOBBY
    var options: BluffMarketOptions = BluffMarketOptions()
        private set

    val market: MutableList<BluffCard> = mutableListOf()
    var currentIndex: Int = 0
    var activeTrade: BluffTrade? = null
    var lastEvent: String? = null
    val cardCatalog: MutableMap<String, BluffCard> = mutableMapOf()

    val current: BluffPlayer? get() = if (seating.isEmpty()) null else players[seating[currentIndex]]
    val canStart: Boolean get() = phase == BluffMarketPhase.LOBBY && players.size in 3..6

    fun addPlayer(id: String, name: String, isHost: Boolean = false): BluffPlayer {
        val p = BluffPlayer(id, name, isHost); players[id] = p; return p
    }
    fun removePlayer(id: String) { if (phase == BluffMarketPhase.LOBBY) players.remove(id) }

    fun setOptions(o: BluffMarketOptions) {
        if (phase != BluffMarketPhase.LOBBY) return
        options = o.copy(turnsPerPlayer = o.turnsPerPlayer.coerceIn(2, 8))
    }

    private fun buildDeck(): List<BluffCard> {
        val n = players.size
        val spec: List<Pair<Int, Int>> = when {
            n <= 3 -> listOf(1 to 3, 2 to 3, 5 to 2, 10 to 1, 15 to 1, 20 to 1)
            n == 4 -> listOf(1 to 3, 2 to 3, 5 to 3, 10 to 2, 15 to 1, 20 to 1)
            n >= 6 -> listOf(1 to 5, 2 to 5, 5 to 3, 10 to 3, 15 to 2, 20 to 1)
            else   -> listOf(1 to 4, 2 to 4, 5 to 3, 10 to 2, 15 to 2, 20 to 1)
        }
        val cards = ArrayList<BluffCard>()
        var seq = 0
        for ((v, copies) in spec) {
            repeat(copies) {
                seq += 1
                cards.add(BluffCard("P$v-$seq", BluffKind.Points(v)))
            }
        }
        val bombCount = if (options.twoBombs) 2 else 1
        repeat(bombCount) { cards.add(BluffCard("B-${it + 1}", BluffKind.Bomb(-25))) }
        if (options.wildcard) cards.add(BluffCard("W-1", BluffKind.Wildcard))
        return cards.shuffled(rng)
    }

    fun start() {
        if (!canStart) return
        seating.clear(); seating.addAll(players.keys.shuffled(rng))
        for (p in players.values) {
            p.hand.clear(); p.coins = 0; p.turnsTaken = 0; p.guaranteeUsed = false
        }
        market.clear()
        cardCatalog.clear()
        activeTrade = null
        val deck = buildDeck()
        for (c in deck) cardCatalog[c.id] = c
        var ix = 0
        repeat(3) {
            for (pid in seating) {
                if (ix < deck.size) {
                    players[pid]!!.hand.add(deck[ix]); ix += 1
                }
            }
        }
        while (ix < deck.size) { market.add(deck[ix]); ix += 1 }
        currentIndex = 0
        phase = BluffMarketPhase.PLAYING
        lastEvent = "Round started — ${current!!.name} goes first"
    }

    fun buyFromMarket(playerId: String): String? {
        if (phase != BluffMarketPhase.PLAYING) return "not playing"
        val p = players[playerId] ?: return "unknown player"
        if (p.id != current!!.id) return "not your turn"
        if (activeTrade != null) return "trade in flight"
        if (market.isEmpty()) return "market is empty"
        val c = market.removeAt(market.size - 1)
        p.hand.add(c)
        finishTurn(p)
        lastEvent = "${p.name} bought from the market"
        return null
    }

    fun sellToMarket(playerId: String, cardId: String): String? {
        if (phase != BluffMarketPhase.PLAYING) return "not playing"
        val p = players[playerId] ?: return "unknown player"
        if (p.id != current!!.id) return "not your turn"
        if (activeTrade != null) return "trade in flight"
        val idx = p.hand.indexOfFirst { it.id == cardId }
        if (idx < 0) return "card not in hand"
        val c = p.hand.removeAt(idx)
        market.add(c)
        p.coins += 2
        finishTurn(p)
        lastEvent = "${p.name} sold to the market for 2"
        return null
    }

    fun proposeTrade(playerId: String, targetId: String, cardId: String): String? {
        if (phase != BluffMarketPhase.PLAYING) return "not playing"
        val p = players[playerId] ?: return "unknown player"
        if (p.id != current!!.id) return "not your turn"
        if (activeTrade != null) return "trade in flight"
        if (targetId == playerId) return "can't trade with yourself"
        if (players[targetId] == null) return "unknown target"
        if (p.hand.none { it.id == cardId }) return "card not in hand"
        val t = BluffTrade(playerId, targetId)
        t.proposerCardId = cardId
        activeTrade = t
        lastEvent = "${p.name} proposes a trade with ${players[targetId]!!.name}"
        return null
    }

    fun counterTrade(playerId: String, cardId: String): String? {
        val t = activeTrade ?: return "no active trade"
        if (t.targetId != playerId) return "not your trade"
        val p = players[playerId] ?: return "unknown player"
        if (p.hand.none { it.id == cardId }) return "card not in hand"
        t.targetCardId = cardId
        lastEvent = "${p.name} committed a counter-card"
        return null
    }

    fun declineTrade(playerId: String): String? {
        val t = activeTrade ?: return "no active trade"
        if (playerId != t.targetId && playerId != t.proposerId) return "not your trade"
        val name = players[playerId]?.name ?: "?"
        activeTrade = null
        // Cancelling a trade does NOT end the proposer's turn — they must
        // still buy, sell, or complete a trade, so a trade can't be used to
        // skip a turn.
        lastEvent = "$name cancelled the trade"
        return null
    }

    fun useGuarantee(playerId: String): String? {
        val t = activeTrade ?: return "no active trade"
        if (playerId != t.proposerId && playerId != t.targetId) return "not your trade"
        val p = players[playerId] ?: return "unknown player"
        if (p.guaranteeUsed) return "guarantee already used"
        p.guaranteeUsed = true
        if (playerId == t.proposerId) t.proposerGuarantee = true else t.targetGuarantee = true
        lastEvent = "${p.name} invoked The Guarantee!"
        return null
    }

    fun respondTrade(playerId: String, accept: Boolean): String? {
        val t = activeTrade ?: return "no active trade"
        if (!t.revealed) return "wait for both sides to commit"
        if (playerId != t.proposerId && playerId != t.targetId) return "not your trade"
        if (playerId == t.proposerId) t.proposerAccept = accept else t.targetAccept = accept
        if (t.proposerAccept != null && t.targetAccept != null) settleTrade()
        return null
    }

    private fun settleTrade() {
        val t = activeTrade ?: return
        val forced = t.proposerGuarantee || t.targetGuarantee
        val agreed = (t.proposerAccept == true && t.targetAccept == true) || forced
        val proposer = players[t.proposerId]!!
        val target = players[t.targetId]!!
        var completed = false
        if (agreed) {
            val pcid = t.proposerCardId
            val tcid = t.targetCardId
            val pIdx = proposer.hand.indexOfFirst { it.id == pcid }
            val tIdx = target.hand.indexOfFirst { it.id == tcid }
            if (pcid != null && tcid != null && pIdx >= 0 && tIdx >= 0) {
                val pCard = proposer.hand.removeAt(pIdx)
                val tCard = target.hand.removeAt(tIdx)
                proposer.hand.add(tCard)
                target.hand.add(pCard)
                lastEvent = "${proposer.name} ⇆ ${target.name} — trade completed"
                completed = true
            }
        }
        if (!completed) {
            lastEvent = "${proposer.name} ⇆ ${target.name} — trade cancelled"
        }
        activeTrade = null
        // Only a completed swap consumes the proposer's turn; a rejected
        // trade leaves it their turn so trading can't be used to skip.
        if (completed) finishTurn(proposer)
    }

    private fun finishTurn(p: BluffPlayer) {
        p.turnsTaken += 1
        if (players.values.all { it.turnsTaken >= options.turnsPerPlayer }) {
            phase = BluffMarketPhase.SCORING
            return
        }
        advanceTurn()
    }

    private fun advanceTurn() {
        if (seating.isEmpty()) return
        currentIndex = (currentIndex + 1) % seating.size
    }

    data class ScoreRow(
        val id: String, val name: String, val total: Int,
        val sum: Int, val coins: Int, val hasBomb: Boolean,
    )

    fun score(): List<ScoreRow> = seating.mapNotNull { pid ->
        val p = players[pid] ?: return@mapNotNull null
        val sum = p.hand.sumOf { it.points }
        val hasBomb = p.hand.any { it.kind is BluffKind.Bomb }
        ScoreRow(p.id, p.name, sum + p.coins, sum, p.coins, hasBomb)
    }

    fun finalize() { if (phase == BluffMarketPhase.SCORING) phase = BluffMarketPhase.GAME_OVER }

    fun reset() {
        phase = BluffMarketPhase.LOBBY
        for (p in players.values) {
            p.hand.clear(); p.coins = 0; p.turnsTaken = 0; p.guaranteeUsed = false
        }
        market.clear(); cardCatalog.clear()
        activeTrade = null; lastEvent = null; currentIndex = 0
    }
}
