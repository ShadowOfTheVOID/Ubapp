package com.example.ubapp.games.crazyeights

import kotlin.random.Random

enum class Suit(val short: String, val glyph: String) {
    CLUBS("C", "♣"), DIAMONDS("D", "♦"), HEARTS("H", "♥"), SPADES("S", "♠");
    val isRed: Boolean get() = this == DIAMONDS || this == HEARTS
}

/** rank 2..14 (J=11, Q=12, K=13, A=14). */
data class Card(val suit: Suit, val rank: Int) {
    val rankShort: String get() = when (rank) { 11 -> "J"; 12 -> "Q"; 13 -> "K"; 14 -> "A"; else -> "$rank" }
    val id: String get() = "${suit.short}$rank"
    override fun toString() = "$rankShort${suit.glyph}"
}

fun standardDeck(): List<Card> =
    Suit.entries.flatMap { s -> (2..14).map { Card(s, it) } }

enum class CrazyEightsPhase { LOBBY, PLAYING, GAME_OVER }

/** Host-configurable house rules. Defaults reproduce the classic game. */
data class CrazyEightsOptions(
    val startingHandSize: Int? = null,
    val jackSkips: Boolean = false,
    val queenReverses: Boolean = false,
    /** Playing a 2 forces the next player to draw two cards and lose their turn. */
    val twosDrawTwo: Boolean = false,
)

class CrazyEightsPlayer(val id: String, val name: String, val isHost: Boolean) {
    val hand: MutableList<Card> = mutableListOf()
}

/**
 * Classic Crazy Eights:
 *  - Match top card by suit or rank
 *  - 8s are wild — player picks new active suit
 *  - If you can't play, draw one card (if it's playable, you may play it)
 *  - First empty hand wins
 */
class CrazyEightsEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, CrazyEightsPlayer> = linkedMapOf()
    private val order: MutableList<String> = mutableListOf()
    var phase: CrazyEightsPhase = CrazyEightsPhase.LOBBY
    var options: CrazyEightsOptions = CrazyEightsOptions()
        private set

    val drawPile: MutableList<Card> = mutableListOf()
    val discardPile: MutableList<Card> = mutableListOf()
    /** Overrides top card suit when an 8 is played. */
    var activeSuit: Suit? = null
    var currentIndex: Int = 0
    var justDrew: Boolean = false
    private var direction: Int = 1
    var winnerId: String? = null
    var lastEvent: String? = null
    /** Consecutive turns where the draw pile is exhausted and can't be
     *  replenished and the player can't act. A full lap of these ends the
     *  game so a blocked board doesn't loop forever. */
    private var stalePasses = 0

    val current: CrazyEightsPlayer? get() = if (order.isEmpty()) null else players[order[currentIndex]]
    val topCard: Card? get() = discardPile.lastOrNull()
    val activeOrTopSuit: Suit get() = activeSuit ?: topCard!!.suit

    fun addPlayer(id: String, name: String, isHost: Boolean = false): CrazyEightsPlayer {
        val p = CrazyEightsPlayer(id, name, isHost); players[id] = p; return p
    }
    fun removePlayer(id: String) { if (phase == CrazyEightsPhase.LOBBY) players.remove(id) }
    val canStart: Boolean get() = phase == CrazyEightsPhase.LOBBY && players.size in 2..8

    fun setOptions(o: CrazyEightsOptions) {
        if (phase != CrazyEightsPhase.LOBBY) return
        options = o.copy(startingHandSize = o.startingHandSize?.coerceIn(3, 10))
    }

    fun start() {
        if (!canStart) return
        drawPile.clear(); discardPile.clear(); activeSuit = null; direction = 1
        drawPile.addAll(standardDeck().shuffled(rng))
        val dealCount = options.startingHandSize ?: (if (players.size == 2) 7 else 5)
        stalePasses = 0
        order.clear(); order.addAll(players.keys.shuffled(rng))
        repeat(dealCount) {
            for (pid in order) players[pid]!!.hand.add(drawPile.removeAt(drawPile.size - 1))
        }
        while (drawPile.isNotEmpty()) {
            val c = drawPile.removeAt(drawPile.size - 1)
            discardPile.add(c)
            if (c.rank != 8) break
        }
        currentIndex = 0; justDrew = false
        phase = CrazyEightsPhase.PLAYING
        lastEvent = "${current!!.name} starts"
    }

    fun canPlay(c: Card): Boolean {
        val top = topCard ?: return true
        if (c.rank == 8) return true
        if (c.suit == activeOrTopSuit) return true
        if (c.rank == top.rank) return true
        return false
    }

    /** Returns null on success, an error message on failure. */
    fun playCard(playerId: String, card: Card, declaredSuit: Suit? = null): String? {
        if (phase != CrazyEightsPhase.PLAYING) return "not playing"
        val p = players[playerId] ?: return "unknown player"
        if (p.id != current!!.id) return "not your turn"
        if (!p.hand.contains(card)) return "card not in hand"
        if (!canPlay(card)) return "card does not match"
        if (card.rank == 8 && declaredSuit == null) return "must declare a suit"
        p.hand.remove(card)
        discardPile.add(card)
        stalePasses = 0
        activeSuit = if (card.rank == 8) declaredSuit else null
        justDrew = false
        if (options.queenReverses && card.rank == 12 && order.size > 2) direction = -direction
        val skipNext = options.jackSkips && card.rank == 11 && order.size > 2
        lastEvent = if (card.rank == 8) "${p.name} played $card → ${declaredSuit!!.glyph}"
                    else "${p.name} played $card"
        if (p.hand.isEmpty()) {
            phase = CrazyEightsPhase.GAME_OVER; winnerId = p.id; return null
        }
        advanceTurn()
        if (skipNext) advanceTurn()
        if (options.twosDrawTwo && card.rank == 2 && order.size >= 2) {
            val victim = current!!
            repeat(2) {
                if (drawPile.isEmpty()) reshuffle()
                if (drawPile.isNotEmpty()) victim.hand.add(drawPile.removeAt(drawPile.size - 1))
            }
            lastEvent = "${victim.name} draws two and is skipped"
            advanceTurn()
        }
        return null
    }

    fun drawOne(playerId: String): Card? {
        if (phase != CrazyEightsPhase.PLAYING) return null
        val p = players[playerId] ?: return null
        if (p.id != current!!.id) return null
        if (drawPile.isEmpty()) reshuffle()
        if (drawPile.isEmpty()) {
            stalePasses += 1
            if (stalePasses >= order.size) {
                phase = CrazyEightsPhase.GAME_OVER
                var best = order[0]
                for (pid in order) if (players[pid]!!.hand.size < players[best]!!.hand.size) best = pid
                winnerId = best
                lastEvent = "Stalemate — ${players[best]!!.name} wins with the fewest cards"
                return null
            }
            advanceTurn(); return null
        }
        val c = drawPile.removeAt(drawPile.size - 1)
        p.hand.add(c)
        stalePasses = 0
        lastEvent = "${p.name} drew a card"
        if (canPlay(c)) { justDrew = true; return c }
        justDrew = false; advanceTurn(); return c
    }

    fun passAfterDraw(playerId: String) {
        if (phase != CrazyEightsPhase.PLAYING) return
        val p = players[playerId] ?: return
        if (p.id != current!!.id || !justDrew) return
        justDrew = false
        lastEvent = "${p.name} passed"
        advanceTurn()
    }

    private fun advanceTurn() {
        val n = order.size
        currentIndex = ((currentIndex + direction) % n + n) % n
        justDrew = false
    }

    private fun reshuffle() {
        if (discardPile.size <= 1) return
        val top = discardPile.removeAt(discardPile.size - 1)
        drawPile.addAll(discardPile.shuffled(rng))
        discardPile.clear(); discardPile.add(top)
    }

    fun reset() {
        phase = CrazyEightsPhase.LOBBY
        drawPile.clear(); discardPile.clear()
        activeSuit = null; currentIndex = 0; justDrew = false; direction = 1
        stalePasses = 0
        winnerId = null; lastEvent = null
        for (p in players.values) p.hand.clear()
    }
}
