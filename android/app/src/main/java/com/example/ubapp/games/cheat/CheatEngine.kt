package com.example.ubapp.games.cheat

import kotlin.random.Random

/** Standard 52-card deck for Cheat. Distinct from Crazy Eights' types so
 *  the engines stay independent. */
enum class CheatSuit(val short: String, val glyph: String) {
    CLUBS("C", "♣"), DIAMONDS("D", "♦"), HEARTS("H", "♥"), SPADES("S", "♠");
    val isRed: Boolean get() = this == DIAMONDS || this == HEARTS
}

/** rank 1..13 where 1 = Ace, 11 = J, 12 = Q, 13 = K. */
data class CheatCard(val suit: CheatSuit, val rank: Int) {
    val rankShort: String get() = when (rank) {
        1 -> "A"; 11 -> "J"; 12 -> "Q"; 13 -> "K"; else -> "$rank"
    }
    val id: String get() = "${suit.short}$rank"
    override fun toString() = "$rankShort${suit.glyph}"
}

fun cheatStandardDeck(): List<CheatCard> =
    CheatSuit.entries.flatMap { s -> (1..13).map { CheatCard(s, it) } }

enum class CheatPhase { LOBBY, PLAYING, PENDING_WIN, GAME_OVER }

data class CheatOptions(
    /** When true, the active player may claim any rank rather than the
     *  next rank in sequence. More chaos, less strategy. */
    val freeClaim: Boolean = false,
)

/** The currently-open play that any non-author can BS-call. */
data class CheatLastPlay(
    val playerId: String,
    val claimedRank: Int,
    val actualCards: List<CheatCard>,
) {
    val count: Int get() = actualCards.size
}

/** Result of the most recent BS call so clients can flash a reveal. */
data class CheatReveal(
    val callerId: String,
    val accusedId: String,
    val claimedRank: Int,
    val cards: List<CheatCard>,
    val truthful: Boolean,
    val loserId: String,
)

class CheatPlayer(val id: String, val name: String, val isHost: Boolean) {
    val hand: MutableList<CheatCard> = mutableListOf()
}

/**
 * Cheat (a.k.a. BS / I Doubt It).
 *
 * Turn cycle:
 *  - The active player plays one or more cards face-down and claims a
 *    rank matching `expectedRank` (or anything if [CheatOptions.freeClaim]).
 *  - Anyone except the player who just played can call BS until the
 *    next play closes the window.
 *  - Calling BS reveals the cards; the loser picks up everything.
 *  - Playing your last card enters [CheatPhase.PENDING_WIN] — any other
 *    player can still call BS or [acceptWin] to confirm.
 */
class CheatEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, CheatPlayer> = linkedMapOf()
    private val order: MutableList<String> = mutableListOf()
    val orderSnapshot: List<String> get() = order.toList()
    var phase: CheatPhase = CheatPhase.LOBBY
    var options: CheatOptions = CheatOptions()
        private set

    /** Closed cards in the pile — values known to engine, hidden to clients. */
    val pile: MutableList<CheatCard> = mutableListOf()
    /** Currently open play; null between plays / at start. */
    var lastPlay: CheatLastPlay? = null
    /** Reveal from the most recent BS call (kept until the next play). */
    var lastReveal: CheatReveal? = null

    /** 1..13. Next rank that must be claimed (unless freeClaim). */
    var expectedRank: Int = 1
    var currentIndex: Int = 0
    var winnerId: String? = null
    var lastEvent: String? = null

    val current: CheatPlayer? get() = if (order.isEmpty()) null else players[order[currentIndex]]
    val canStart: Boolean get() = phase == CheatPhase.LOBBY && players.size in 3..8

    fun addPlayer(id: String, name: String, isHost: Boolean = false): CheatPlayer {
        val p = CheatPlayer(id, name, isHost); players[id] = p; return p
    }
    fun removePlayer(id: String) { if (phase == CheatPhase.LOBBY) players.remove(id) }

    fun setOptions(o: CheatOptions) {
        if (phase != CheatPhase.LOBBY) return
        options = o
    }

    fun start() {
        if (!canStart) return
        val deck = cheatStandardDeck().shuffled(rng)
        order.clear(); order.addAll(players.keys.shuffled(rng))
        for (p in players.values) p.hand.clear()
        for ((i, c) in deck.withIndex()) {
            players[order[i % order.size]]!!.hand.add(c)
        }
        for (p in players.values) {
            p.hand.sortWith(compareBy({ it.rank }, { it.suit.ordinal }))
        }
        pile.clear()
        lastPlay = null
        lastReveal = null
        expectedRank = 1
        currentIndex = 0
        winnerId = null
        phase = CheatPhase.PLAYING
        lastEvent = "${current!!.name} starts — claim Aces"
    }

    /** Returns null on success, an error message on failure. */
    fun play(playerId: String, cards: List<CheatCard>, claimedRank: Int): String? {
        if (phase == CheatPhase.PENDING_WIN) return "round is pending — call BS or accept"
        if (phase != CheatPhase.PLAYING) return "not playing"
        val p = players[playerId] ?: return "unknown player"
        if (p.id != current!!.id) return "not your turn"
        if (cards.isEmpty()) return "play at least one card"
        if (claimedRank !in 1..13) return "bad rank"
        if (!options.freeClaim && claimedRank != expectedRank) {
            return "must claim ${rankName(expectedRank)}"
        }
        val remaining = p.hand.toMutableList()
        for (c in cards) {
            val idx = remaining.indexOf(c)
            if (idx < 0) return "card not in hand"
            remaining.removeAt(idx)
        }
        lastPlay?.let { pile.addAll(it.actualCards) }
        p.hand.clear(); p.hand.addAll(remaining)
        lastPlay = CheatLastPlay(p.id, claimedRank, cards.toList())
        lastReveal = null
        lastEvent = "${p.name} claims ${cards.size} ${rankName(claimedRank)}"
        if (p.hand.isEmpty()) {
            phase = CheatPhase.PENDING_WIN
            winnerId = p.id
            return null
        }
        advanceTurn()
        if (!options.freeClaim) expectedRank = nextRank(claimedRank)
        return null
    }

    fun callBs(callerId: String): String? {
        if (phase != CheatPhase.PLAYING && phase != CheatPhase.PENDING_WIN) return "not playing"
        val lp = lastPlay ?: return "nothing to call"
        if (players[callerId] == null) return "unknown caller"
        if (callerId == lp.playerId) return "can't BS your own play"
        val truthful = lp.actualCards.all { it.rank == lp.claimedRank }
        val loserId = if (truthful) callerId else lp.playerId
        val loser = players[loserId]!!
        val accusedName = players[lp.playerId]!!.name
        val callerName = players[callerId]!!.name
        val pickup = pile.toMutableList()
        pickup.addAll(lp.actualCards)
        loser.hand.addAll(pickup)
        loser.hand.sortWith(compareBy({ it.rank }, { it.suit.ordinal }))
        pile.clear()
        lastReveal = CheatReveal(callerId, lp.playerId, lp.claimedRank, lp.actualCards, truthful, loserId)
        lastPlay = null
        lastEvent = if (truthful)
            "$callerName called BS on $accusedName — truthful. $callerName picks up ${pickup.size}."
        else
            "$callerName called BS on $accusedName — caught! $accusedName picks up ${pickup.size}."
        if (phase == CheatPhase.PENDING_WIN) {
            if (truthful) {
                phase = CheatPhase.GAME_OVER
            } else {
                winnerId = null
                phase = CheatPhase.PLAYING
                currentIndex = (indexOf(lp.playerId) + 1) % order.size
                if (!options.freeClaim) expectedRank = nextRank(lp.claimedRank)
            }
        } else {
            currentIndex = (indexOf(loserId) + 1) % order.size
        }
        return null
    }

    fun acceptWin(playerId: String): String? {
        if (phase != CheatPhase.PENDING_WIN) return "no pending win"
        val wid = winnerId ?: return "no winner"
        if (playerId == wid) return "winner can't accept their own win"
        if (players[playerId] == null) return "unknown player"
        phase = CheatPhase.GAME_OVER
        lastEvent = "${players[playerId]!!.name} accepted ${players[wid]!!.name}'s win"
        return null
    }

    fun reset() {
        phase = CheatPhase.LOBBY
        for (p in players.values) p.hand.clear()
        pile.clear(); lastPlay = null; lastReveal = null
        winnerId = null; lastEvent = null
        expectedRank = 1; currentIndex = 0
    }

    private fun advanceTurn() {
        currentIndex = (currentIndex + 1) % order.size
    }
    private fun indexOf(id: String): Int {
        val i = order.indexOf(id); return if (i < 0) 0 else i
    }

    /** Aces (1) → 2 → 3 … → K (13) → Aces. */
    fun nextRank(r: Int): Int = (r % 13) + 1

    fun rankName(r: Int): String = when (r) {
        1 -> "Aces"; 11 -> "Jacks"; 12 -> "Queens"; 13 -> "Kings"; else -> "${r}s"
    }
}
