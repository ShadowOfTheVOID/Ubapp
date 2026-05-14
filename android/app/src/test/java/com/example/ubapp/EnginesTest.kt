package com.example.ubapp

import com.example.ubapp.games.connectfour.ConnectFourAI
import com.example.ubapp.games.connectfour.ConnectFourModel
import com.example.ubapp.games.connectfour.Disc
import com.example.ubapp.games.crazyeights.CrazyEightsEngine
import com.example.ubapp.games.crazyeights.CrazyEightsPhase
import com.example.ubapp.games.crazyeights.Card as CECard
import com.example.ubapp.games.crazyeights.Suit
import com.example.ubapp.games.tag.PlayerStatus
import com.example.ubapp.games.tag.TagEngine
import com.example.ubapp.games.tag.TagVariant
import com.example.ubapp.games.tictactoe.Mark
import com.example.ubapp.games.tictactoe.Minimax
import com.example.ubapp.games.tictactoe.TicTacToeModel
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TicTacToeTest {
    @Test fun `optimal play from empty board never loses`() {
        // Self-play with minimax should always draw.
        val m = TicTacToeModel()
        while (!m.isOver) {
            val ai = if (m.current == Mark.X) Mark.X else Mark.O
            val move = Minimax.bestMove(m, ai)
            assertNotNull(move)
            m.apply(move)
        }
        assertNull(m.winner)
        assertTrue(m.isDraw)
    }

    @Test fun `winner detection across all eight lines`() {
        val cases = listOf(
            listOf(0,1,2), listOf(3,4,5), listOf(6,7,8),
            listOf(0,3,6), listOf(1,4,7), listOf(2,5,8),
            listOf(0,4,8), listOf(2,4,6),
        )
        for (line in cases) {
            val m = TicTacToeModel()
            for (i in 0..8) m.board[i] = Mark.EMPTY
            for (i in line) m.board[i] = Mark.X
            assertEquals(Mark.X, m.winner)
        }
    }
}

class ConnectFourTest {
    @Test fun `bottom-row four wins`() {
        val m = ConnectFourModel()
        // RYRYRYR setup pattern across the bottom — only fill first 4 reds.
        m.board[0][0] = Disc.RED; m.board[1][0] = Disc.RED
        m.board[2][0] = Disc.RED; m.board[3][0] = Disc.RED
        assertEquals(Disc.RED, m.winner)
    }

    @Test fun `AI blocks an obvious immediate win`() {
        // Set up: red has three in a row on the bottom (cols 0..2); yellow must drop in col 3.
        val m = ConnectFourModel()
        m.board[0][0] = Disc.RED; m.board[1][0] = Disc.RED; m.board[2][0] = Disc.RED
        m.current = Disc.YELLOW
        val move = ConnectFourAI.bestMove(m, Disc.YELLOW, depth = 4)
        assertEquals(3, move)
    }
}

class CrazyEightsTest {
    @Test fun `play matches suit or rank`() {
        val e = CrazyEightsEngine(Random(3))
        e.addPlayer("a", "Alice"); e.addPlayer("b", "Bob")
        e.start()
        val curr = e.current!!
        val top = e.topCard!!
        // First playable card from current hand.
        val playable = curr.hand.first { e.canPlay(it) }
        assertNull(e.playCard(curr.id, playable,
            if (playable.rank == 8) Suit.HEARTS else null))
        assertEquals(playable, e.topCard)
        assertFalse(curr.hand.contains(playable))
        // Top card moved on; turn passes.
        assertEquals(if (curr.id == "a") "b" else "a", e.current!!.id)
        @Suppress("UNUSED_EXPRESSION") top  // referenced for clarity
    }

    @Test fun `eight is wild and sets active suit`() {
        val e = CrazyEightsEngine(Random(9))
        e.addPlayer("a", "A"); e.addPlayer("b", "B")
        e.start()
        val curr = e.current!!
        // Force an 8 of clubs into the hand and onto the top.
        val eight = CECard(Suit.CLUBS, 8)
        curr.hand.add(0, eight)
        // Make sure top card differs by both suit & rank so the only legal
        // reason to play this is "rank == 8".
        e.discardPile.clear()
        e.discardPile.add(CECard(Suit.HEARTS, 5))
        assertTrue(e.canPlay(eight))
        e.playCard(curr.id, eight, declaredSuit = Suit.DIAMONDS)
        assertEquals(Suit.DIAMONDS, e.activeSuit)
        assertEquals(Suit.DIAMONDS, e.activeOrTopSuit)
    }

    @Test fun `empty hand wins`() {
        val e = CrazyEightsEngine(Random(4))
        e.addPlayer("a", "A"); e.addPlayer("b", "B")
        e.start()
        val curr = e.current!!
        // Force a hand of exactly one playable card.
        val top = e.topCard!!
        val winning = CECard(top.suit, if (top.rank == 10) 9 else 10)
        curr.hand.clear()
        curr.hand.add(winning)
        e.playCard(curr.id, winning)
        assertEquals(CrazyEightsPhase.GAME_OVER, e.phase)
        assertEquals(curr.id, e.winnerId)
    }
}

class TagEngineTest {
    @Test fun `classic tag transfers it on touch`() {
        val e = TagEngine("a")
        e.start(TagVariant.CLASSIC, "a", 0L,
                listOf("a", "b", "c"), mapOf("a" to "A", "b" to "B", "c" to "C"))
        assertEquals(PlayerStatus.IT, e.state!!.players["a"]!!.status)
        assertTrue(e.applyTag("a", "b"))
        assertEquals(PlayerStatus.RUNNER, e.state!!.players["a"]!!.status)
        assertEquals(PlayerStatus.IT, e.state!!.players["b"]!!.status)
    }

    @Test fun `freeze tag ends round when all runners frozen`() {
        val e = TagEngine("it")
        e.start(TagVariant.FREEZE, "it", 0L,
                listOf("it", "x", "y"), mapOf("it" to "It", "x" to "X", "y" to "Y"))
        e.applyTag("it", "x")
        e.applyTag("it", "y")
        assertNotNull(e.state!!.endReason)
        assertEquals("it", e.state!!.winnerId)
    }
}
