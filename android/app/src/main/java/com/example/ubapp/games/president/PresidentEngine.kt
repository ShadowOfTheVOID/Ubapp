package com.example.ubapp.games.president

import kotlin.random.Random

/** Standard 52-card deck for President. Distinct from Crazy Eights / Cheat
 *  so the engines stay independent. Card power for trick-comparison: 3
 *  (lowest) → A → 2 (highest). */
enum class PresSuit(val short: String, val glyph: String) {
    CLUBS("C", "♣"), DIAMONDS("D", "♦"), HEARTS("H", "♥"), SPADES("S", "♠");
    val isRed: Boolean get() = this == DIAMONDS || this == HEARTS
}

/** rank 2..14 where 2 = two (highest), 11..13 = J/Q/K, 14 = A. */
data class PresCard(val suit: PresSuit, val rank: Int) {
    val rankShort: String get() = when (rank) {
        11 -> "J"; 12 -> "Q"; 13 -> "K"; 14 -> "A"; else -> "$rank"
    }
    val id: String get() = "${suit.short}$rank"
    override fun toString() = "$rankShort${suit.glyph}"
    /** Power: 3..14 keep value (3 low, A=14), 2 → 15 (top). */
    val power: Int get() = if (rank == 2) 15 else rank
}

fun presStandardDeck(): List<PresCard> =
    PresSuit.entries.flatMap { s -> (2..14).map { PresCard(s, it) } }

enum class PresidentPhase { LOBBY, SWAPPING, PLAYING, GAME_OVER }

enum class PresRank(val label: String) {
    PRESIDENT("President"),
    VICE_PRESIDENT("Vice President"),
    VICE_SCUM("Vice Scum"),
    SCUM("Scum"),
    NEUTRAL("Neutral");

    fun wireValue(): String = when (this) {
        PRESIDENT -> "president"; VICE_PRESIDENT -> "vicePresident"
        VICE_SCUM -> "viceScum"; SCUM -> "scum"; NEUTRAL -> "neutral"
    }
}

/** One play in the current trick. */
sealed class PresCombo {
    object Single : PresCombo()
    object Pair : PresCombo()
    object Triple : PresCombo()
    object Quad : PresCombo()
    /** Run of pairs (consecutive ranks, length 2..6 pairs). */
    data class RunOfPairs(val length: Int) : PresCombo()
}

data class PresOptions(
    /** President can announce a house rule each round (chat-enforced). */
    val allowHouseRules: Boolean = false,
    /** Display-only: revolution rule (4-of-a-kind inverts trick). */
    val revolution: Boolean = false,
)

class PresidentPlayer(val id: String, val name: String, val isHost: Boolean) {
    val hand: MutableList<PresCard> = mutableListOf()
    var rank: PresRank = PresRank.NEUTRAL
    var finished: Boolean = false
    /** 1-based finishing order. 0 if not finished. */
    var finishOrder: Int = 0
}

data class PresTrick(val combo: PresCombo, val topPower: Int, val leaderId: String)

data class PresLastPlay(
    val playerId: String,
    val cards: List<PresCard>,
    val combo: PresCombo,
)

data class PresSwap(
    val fromId: String,
    val toId: String,
    val count: Int,
    /** True if the giver picks cards (Pres-back, VP-back); false for
     *  Scum→Pres / VS→VP which give their best automatically. */
    val giverChooses: Boolean,
    var cards: List<PresCard>? = null,
)

/** Pure President / Scum / Asshole engine. */
class PresidentEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, PresidentPlayer> = linkedMapOf()
    private val seating: MutableList<String> = mutableListOf()
    val seatingSnapshot: List<String> get() = seating.toList()
    var phase: PresidentPhase = PresidentPhase.LOBBY
    var options: PresOptions = PresOptions()
        private set

    var trick: PresTrick? = null
    val passedThisTrick: MutableSet<String> = mutableSetOf()
    var lastPlay: PresLastPlay? = null
    val finishOrder: MutableList<String> = mutableListOf()
    val pendingSwaps: MutableList<PresSwap> = mutableListOf()

    var currentIndex: Int = 0
    var lastEvent: String? = null
    var roundNumber: Int = 0

    val current: PresidentPlayer? get() = if (seating.isEmpty()) null else players[seating[currentIndex]]
    val canStart: Boolean get() = phase == PresidentPhase.LOBBY && players.size in 4..7

    fun addPlayer(id: String, name: String, isHost: Boolean = false): PresidentPlayer {
        val p = PresidentPlayer(id, name, isHost); players[id] = p; return p
    }
    fun removePlayer(id: String) { if (phase == PresidentPhase.LOBBY) players.remove(id) }

    fun setOptions(o: PresOptions) {
        if (phase != PresidentPhase.LOBBY) return
        options = o
    }

    fun start() {
        if (!canStart) return
        seating.clear(); seating.addAll(players.keys.shuffled(rng))
        for (p in players.values) {
            p.rank = PresRank.NEUTRAL; p.finished = false; p.finishOrder = 0; p.hand.clear()
        }
        finishOrder.clear(); passedThisTrick.clear()
        trick = null; lastPlay = null
        roundNumber = 1
        deal()
        val leadId = seating.firstOrNull { players[it]!!.hand.contains(PresCard(PresSuit.CLUBS, 3)) }
        currentIndex = leadId?.let { seating.indexOf(it) } ?: 0
        phase = PresidentPhase.PLAYING
        lastEvent = "Round 1 — ${current!!.name} leads with 3♣"
    }

    fun startNextRound() {
        if (phase != PresidentPhase.GAME_OVER || finishOrder.isEmpty()) return
        assignRanks()
        roundNumber += 1
        for (p in players.values) { p.hand.clear(); p.finished = false; p.finishOrder = 0 }
        finishOrder.clear(); trick = null; lastPlay = null; passedThisTrick.clear()
        deal()
        pendingSwaps.clear()
        pendingSwaps.addAll(swapPlan())
        if (pendingSwaps.isEmpty()) {
            startTricksAfterSwaps()
        } else {
            phase = PresidentPhase.SWAPPING
            lastEvent = "Round $roundNumber — swap phase"
        }
    }

    fun submitSwap(fromId: String, cards: List<PresCard>): String? {
        if (phase != PresidentPhase.SWAPPING) return "not in swap phase"
        val idx = pendingSwaps.indexOfFirst { it.fromId == fromId && it.cards == null }
        if (idx < 0) return "no pending swap for you"
        val s = pendingSwaps[idx]
        val chosen: List<PresCard> = if (s.giverChooses) {
            if (cards.size != s.count)
                return "give exactly ${s.count} card${if (s.count == 1) "" else "s"}"
            cards
        } else {
            players[fromId]!!.hand.sortedByDescending { it.power }.take(s.count)
        }
        val giverHand = players[fromId]!!.hand.toMutableList()
        for (c in chosen) {
            val i = giverHand.indexOf(c)
            if (i < 0) return "card not in hand"
            giverHand.removeAt(i)
        }
        players[fromId]!!.hand.clear(); players[fromId]!!.hand.addAll(giverHand)
        players[s.toId]!!.hand.addAll(chosen)
        players[s.toId]!!.hand.sortBy { it.power }
        players[fromId]!!.hand.sortBy { it.power }
        pendingSwaps[idx] = s.copy(cards = chosen)
        lastEvent = "${players[fromId]!!.name} gave ${chosen.size} card${if (chosen.size == 1) "" else "s"} to ${players[s.toId]!!.name}"
        if (pendingSwaps.all { it.cards != null }) startTricksAfterSwaps()
        return null
    }

    private fun startTricksAfterSwaps() {
        val pres = finishOrder.firstOrNull()
        currentIndex = if (pres != null) seating.indexOf(pres).coerceAtLeast(0) else 0
        phase = PresidentPhase.PLAYING
        lastEvent = "${current!!.name} (President) leads round $roundNumber"
        pendingSwaps.clear()
        finishOrder.clear()
        for (p in players.values) { p.finished = false; p.finishOrder = 0 }
    }

    fun play(playerId: String, cards: List<PresCard>): String? {
        if (phase != PresidentPhase.PLAYING) return "not playing"
        val p = players[playerId] ?: return "unknown player"
        if (p.id != current!!.id) return "not your turn"
        if (cards.isEmpty()) return "play at least one card"
        val hand = p.hand.toMutableList()
        for (c in cards) {
            val i = hand.indexOf(c)
            if (i < 0) return "card not in hand"
            hand.removeAt(i)
        }
        val combo = classify(cards) ?: return "invalid combination"
        val power = comboPower(combo, cards)
        val t = trick
        if (t != null) {
            if (!sameType(t.combo, combo)) return "must play ${describe(t.combo)}"
            if (power <= t.topPower) return "must play higher than ${t.topPower}"
        } else if (roundNumber == 1 && lastPlay == null
                  && p.hand.contains(PresCard(PresSuit.CLUBS, 3))
                  && !cards.contains(PresCard(PresSuit.CLUBS, 3))) {
            return "first play must include 3♣"
        }
        p.hand.clear(); p.hand.addAll(hand)
        trick = PresTrick(combo, power, t?.leaderId ?: p.id)
        lastPlay = PresLastPlay(p.id, cards.toList(), combo)
        passedThisTrick.clear()
        lastEvent = "${p.name} played ${formatCards(cards)} (${describe(combo)})"
        if (p.hand.isEmpty()) {
            p.finished = true
            finishOrder.add(p.id)
            p.finishOrder = finishOrder.size
        }
        if (remainingPlayers().size <= 1) {
            for (sid in seating) {
                val pl = players[sid] ?: continue
                if (!pl.finished) {
                    pl.finished = true
                    finishOrder.add(pl.id)
                    pl.finishOrder = finishOrder.size
                }
            }
            assignRanks()
            phase = PresidentPhase.GAME_OVER
            lastEvent = "Round over"
            return null
        }
        advanceTurn()
        return null
    }

    fun pass(playerId: String): String? {
        if (phase != PresidentPhase.PLAYING) return "not playing"
        val p = players[playerId] ?: return "unknown player"
        if (p.id != current!!.id) return "not your turn"
        if (trick == null) return "lead — can't pass"
        passedThisTrick.add(p.id)
        lastEvent = "${p.name} passed"
        val lp = lastPlay
        val alive = remainingPlayers().filter { !it.finished }.map { it.id }
        if (lp != null && alive.all { it == lp.playerId || passedThisTrick.contains(it) }) {
            trick = null
            passedThisTrick.clear()
            val leader = players[lp.playerId]
            if (leader != null && !leader.finished) {
                currentIndex = seating.indexOf(lp.playerId).coerceAtLeast(0)
                lastEvent = "${leader.name} wins the trick and leads"
            } else {
                advanceTurn()
            }
            return null
        }
        advanceTurn()
        return null
    }

    fun reset() {
        phase = PresidentPhase.LOBBY
        for (p in players.values) {
            p.hand.clear(); p.rank = PresRank.NEUTRAL
            p.finished = false; p.finishOrder = 0
        }
        trick = null; lastPlay = null; passedThisTrick.clear()
        finishOrder.clear(); pendingSwaps.clear()
        currentIndex = 0; lastEvent = null; roundNumber = 0
    }

    // ----------------- internals -----------------

    private fun deal() {
        val deck = presStandardDeck().shuffled(rng)
        for ((i, c) in deck.withIndex()) {
            players[seating[i % seating.size]]!!.hand.add(c)
        }
        for (p in players.values) p.hand.sortBy { it.power }
    }

    private fun assignRanks() {
        if (finishOrder.isEmpty()) return
        val n = finishOrder.size
        for ((i, id) in finishOrder.withIndex()) {
            players[id]!!.rank = rankFor(i, n)
            players[id]!!.finishOrder = i + 1
        }
    }

    private fun rankFor(position: Int, total: Int): PresRank = when {
        position == 0 -> PresRank.PRESIDENT
        position == total - 1 -> PresRank.SCUM
        total >= 4 && position == 1 -> PresRank.VICE_PRESIDENT
        total >= 4 && position == total - 2 -> PresRank.VICE_SCUM
        else -> PresRank.NEUTRAL
    }

    private fun swapPlan(): List<PresSwap> {
        val plan = mutableListOf<PresSwap>()
        val pres = players.values.firstOrNull { it.rank == PresRank.PRESIDENT }
        val scum = players.values.firstOrNull { it.rank == PresRank.SCUM }
        val vp = players.values.firstOrNull { it.rank == PresRank.VICE_PRESIDENT }
        val vs = players.values.firstOrNull { it.rank == PresRank.VICE_SCUM }
        if (pres != null && scum != null) {
            plan.add(PresSwap(scum.id, pres.id, 2, giverChooses = false))
            plan.add(PresSwap(pres.id, scum.id, 2, giverChooses = true))
        }
        if (vp != null && vs != null) {
            plan.add(PresSwap(vs.id, vp.id, 1, giverChooses = false))
            plan.add(PresSwap(vp.id, vs.id, 1, giverChooses = true))
        }
        return plan
    }

    private fun advanceTurn() {
        val n = seating.size
        repeat(n) {
            currentIndex = (currentIndex + 1) % n
            val p = players[seating[currentIndex]]!!
            if (!p.finished) return
        }
    }

    fun remainingPlayers(): List<PresidentPlayer> =
        seating.mapNotNull { players[it] }.filter { !it.finished }

    fun classify(cards: List<PresCard>): PresCombo? {
        if (cards.isEmpty()) return null
        val counts = cards.groupingBy { it.rank }.eachCount()
        if (counts.size == 1) return when (cards.size) {
            1 -> PresCombo.Single
            2 -> PresCombo.Pair
            3 -> PresCombo.Triple
            4 -> PresCombo.Quad
            else -> null
        }
        if (counts.values.all { it == 2 } && counts.size >= 2) {
            val ranks = counts.keys.sorted()
            for (i in 1 until ranks.size) if (ranks[i] != ranks[i-1] + 1) return null
            return PresCombo.RunOfPairs(ranks.size)
        }
        return null
    }

    fun comboPower(combo: PresCombo, cards: List<PresCard>): Int =
        cards.maxOfOrNull { it.power } ?: 0

    fun sameType(a: PresCombo, b: PresCombo): Boolean = when {
        a is PresCombo.Single && b is PresCombo.Single -> true
        a is PresCombo.Pair && b is PresCombo.Pair -> true
        a is PresCombo.Triple && b is PresCombo.Triple -> true
        a is PresCombo.Quad && b is PresCombo.Quad -> true
        a is PresCombo.RunOfPairs && b is PresCombo.RunOfPairs -> a.length == b.length
        else -> false
    }

    fun describe(combo: PresCombo): String = when (combo) {
        is PresCombo.Single -> "single"
        is PresCombo.Pair -> "pair"
        is PresCombo.Triple -> "triple"
        is PresCombo.Quad -> "four of a kind"
        is PresCombo.RunOfPairs -> "${combo.length} consecutive pairs"
    }

    private fun formatCards(cards: List<PresCard>): String =
        cards.sortedBy { it.power }.joinToString(" ") { it.toString() }
}
