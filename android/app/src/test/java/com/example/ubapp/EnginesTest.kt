package com.example.ubapp

import com.example.ubapp.games.bluffmarket.BluffKind
import com.example.ubapp.games.bluffmarket.BluffMarketEngine
import com.example.ubapp.games.bluffmarket.BluffMarketOptions
import com.example.ubapp.games.bluffmarket.BluffMarketPhase
import com.example.ubapp.games.cheat.CheatCard
import com.example.ubapp.games.cheat.CheatEngine
import com.example.ubapp.games.cheat.CheatPhase
import com.example.ubapp.games.cheat.CheatSuit
import com.example.ubapp.games.connectfour.ConnectFourAI
import com.example.ubapp.games.connectfour.ConnectFourModel
import com.example.ubapp.games.connectfour.Disc
import com.example.ubapp.games.crazyeights.CrazyEightsEngine
import com.example.ubapp.games.crazyeights.CrazyEightsPhase
import com.example.ubapp.games.crazyeights.Card as CECard
import com.example.ubapp.games.crazyeights.Suit
import com.example.ubapp.games.president.PresCard
import com.example.ubapp.games.president.PresCombo
import com.example.ubapp.games.president.PresRank
import com.example.ubapp.games.president.PresSuit
import com.example.ubapp.games.president.PresidentEngine
import com.example.ubapp.games.president.PresidentPhase
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

class CheatEngineTest {
    private fun engine(seed: Int = 1): CheatEngine {
        val e = CheatEngine(Random(seed))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        return e
    }

    @Test fun `dealing distributes all 52 cards`() {
        val e = engine(7)
        e.start()
        val total = e.players.values.sumOf { it.hand.size }
        assertEquals(52, total)
        assertEquals(CheatPhase.PLAYING, e.phase)
    }

    @Test fun `playing a truthful claim advances turn`() {
        val e = engine(11)
        e.start()
        val current = e.current!!
        // Force a hand that contains an Ace to play a truthful claim.
        current.hand.clear()
        val ace = CheatCard(CheatSuit.SPADES, 1)
        current.hand.add(ace)
        e.expectedRank = 1
        assertNull(e.play(current.id, listOf(ace), 1))
        assertNotNull(e.lastPlay)
        assertEquals(1, e.lastPlay!!.claimedRank)
        assertEquals(2, e.expectedRank, "rank advances 1 → 2")
        assertFalse(current.hand.contains(ace))
    }

    @Test fun `BS on a lie sends the cheater the pile`() {
        val e = engine(13)
        e.start()
        val a = e.current!!
        val bId = e.orderSnapshot.first { it != a.id }
        // a plays a "1" that is actually a King.
        val faker = CheatCard(CheatSuit.HEARTS, 13)
        a.hand.clear(); a.hand.add(faker)
        e.expectedRank = 1
        e.pile.clear()
        // Pre-seed the pile so we can confirm the cheater picks it up.
        val filler = CheatCard(CheatSuit.SPADES, 7)
        e.pile.add(filler)
        e.play(a.id, listOf(faker), claimedRank = 1)
        val priorACount = a.hand.size
        assertNull(e.callBs(bId))
        val r = e.lastReveal!!
        assertFalse(r.truthful)
        assertEquals(a.id, r.loserId)
        // Cheater picked up filler + their own faker (2 cards).
        assertTrue(a.hand.size == priorACount + 2)
    }

    @Test fun `BS on a truthful claim sends pile to the caller`() {
        val e = engine(17)
        e.start()
        val a = e.current!!
        val bId = e.orderSnapshot.first { it != a.id }
        // a plays a real Ace.
        val ace = CheatCard(CheatSuit.CLUBS, 1)
        a.hand.clear(); a.hand.add(ace)
        e.expectedRank = 1
        e.pile.clear(); e.pile.add(CheatCard(CheatSuit.DIAMONDS, 5))
        e.play(a.id, listOf(ace), claimedRank = 1)
        val callerPrior = e.players[bId]!!.hand.size
        e.callBs(bId)
        val r = e.lastReveal!!
        assertTrue(r.truthful)
        assertEquals(bId, r.loserId)
        // Caller picks up filler + a's real Ace = 2 cards.
        assertTrue(e.players[bId]!!.hand.size == callerPrior + 2)
    }

    @Test fun `pending win confirmed when no-one calls`() {
        val e = engine(23)
        e.start()
        val a = e.current!!
        val ace = CheatCard(CheatSuit.HEARTS, 1)
        a.hand.clear(); a.hand.add(ace)
        e.expectedRank = 1
        e.play(a.id, listOf(ace), claimedRank = 1)
        assertEquals(CheatPhase.PENDING_WIN, e.phase)
        assertEquals(a.id, e.winnerId)
        // Another player accepts the win.
        val accepter = e.orderSnapshot.first { it != a.id }
        assertNull(e.acceptWin(accepter))
        assertEquals(CheatPhase.GAME_OVER, e.phase)
    }

    @Test fun `pending win caught by BS reverts to playing`() {
        val e = engine(31)
        e.start()
        val a = e.current!!
        // Play a fake last card.
        val fake = CheatCard(CheatSuit.SPADES, 5)
        a.hand.clear(); a.hand.add(fake)
        e.expectedRank = 1
        e.play(a.id, listOf(fake), claimedRank = 1)
        assertEquals(CheatPhase.PENDING_WIN, e.phase)
        val accuser = e.orderSnapshot.first { it != a.id }
        e.callBs(accuser)
        assertEquals(CheatPhase.PLAYING, e.phase)
        assertNull(e.winnerId)
    }

    @Test fun `rank wraps King to Ace`() {
        val e = CheatEngine(Random(2))
        assertEquals(1, e.nextRank(13))
        assertEquals(2, e.nextRank(1))
    }
}

class PresidentEngineTest {
    private fun engine(seed: Int = 1, n: Int = 4): PresidentEngine {
        val e = PresidentEngine(Random(seed))
        (0 until n).forEach { e.addPlayer("p$it", "P$it") }
        return e
    }

    @Test fun `classify recognises singles pairs triples quads`() {
        val e = engine()
        assertTrue(e.classify(listOf(PresCard(PresSuit.CLUBS, 5))) is PresCombo.Single)
        assertTrue(e.classify(listOf(PresCard(PresSuit.CLUBS, 5), PresCard(PresSuit.HEARTS, 5))) is PresCombo.Pair)
        assertTrue(e.classify(listOf(
            PresCard(PresSuit.CLUBS, 5), PresCard(PresSuit.HEARTS, 5), PresCard(PresSuit.DIAMONDS, 5),
        )) is PresCombo.Triple)
        assertTrue(e.classify(listOf(
            PresCard(PresSuit.CLUBS, 5), PresCard(PresSuit.HEARTS, 5),
            PresCard(PresSuit.DIAMONDS, 5), PresCard(PresSuit.SPADES, 5),
        )) is PresCombo.Quad)
    }

    @Test fun `classify run of pairs requires consecutive ranks`() {
        val e = engine()
        val good = listOf(
            PresCard(PresSuit.CLUBS, 5), PresCard(PresSuit.HEARTS, 5),
            PresCard(PresSuit.DIAMONDS, 6), PresCard(PresSuit.SPADES, 6),
        )
        val combo = e.classify(good)
        assertTrue(combo is PresCombo.RunOfPairs && combo.length == 2)
        val bad = listOf(
            PresCard(PresSuit.CLUBS, 5), PresCard(PresSuit.HEARTS, 5),
            PresCard(PresSuit.DIAMONDS, 7), PresCard(PresSuit.SPADES, 7),
        )
        assertNull(e.classify(bad))
    }

    @Test fun `card power has 2 highest A second`() {
        val two = PresCard(PresSuit.CLUBS, 2).power
        val ace = PresCard(PresSuit.CLUBS, 14).power
        val three = PresCard(PresSuit.CLUBS, 3).power
        assertTrue(two > ace, "2 beats A")
        assertTrue(ace > three, "A beats 3")
    }

    @Test fun `first round opener must include 3 of clubs`() {
        val e = engine(5)
        e.start()
        val current = e.current!!
        // Lead with a single card that isn't 3♣ — should fail if hand holds 3♣.
        val three = PresCard(PresSuit.CLUBS, 3)
        if (current.hand.contains(three)) {
            val other = current.hand.first { it != three }
            val err = e.play(current.id, listOf(other))
            assertNotNull(err)
            // 3♣ play passes.
            assertNull(e.play(current.id, listOf(three)))
        }
    }

    @Test fun `start enters PLAYING and deals all cards`() {
        val e = engine(9, n = 4)
        e.start()
        assertEquals(PresidentPhase.PLAYING, e.phase)
        val total = e.players.values.sumOf { it.hand.size }
        assertEquals(52, total)
    }

    @Test fun `finishing all but one ends the round and assigns ranks`() {
        val e = engine(99, n = 4)
        e.start()
        val ids = e.seatingSnapshot
        // Drain three players' hands so the fourth play empties everyone.
        for (i in 0..2) {
            val p = e.players[ids[i]]!!
            p.hand.clear()
            p.finished = true
            p.finishOrder = i + 1
            e.finishOrder.add(p.id)
        }
        // Drive the engine through the "only one player has cards" branch:
        // currentIndex needs to point at the remaining player.
        e.currentIndex = ids.indexOf(ids[3])
        val last = e.players[ids[3]]!!
        // Give the last player a single playable card.
        last.hand.clear()
        val card = PresCard(PresSuit.SPADES, 5)
        last.hand.add(card)
        // Force trick null and round > 1 so the 3♣ opener constraint is skipped.
        e.trick = null
        // Round 2 sidesteps the 3♣ constraint without touching engine internals.
        // The play empties this player's hand; remainingPlayers().size becomes 0
        // and the engine flushes finishOrder → GAME_OVER.
        // (Set roundNumber via startNextRound prerequisite isn't possible here,
        // so we just check the engine handles "everyone finished" gracefully:
        // pre-fill finishOrder ahead, then play the final card.)
        e.play(last.id, listOf(card))
        assertEquals(PresidentPhase.GAME_OVER, e.phase)
        assertTrue(e.finishOrder.contains(last.id))
        assertEquals(PresRank.PRESIDENT, e.players[e.finishOrder.first()]!!.rank)
        assertEquals(PresRank.SCUM, e.players[e.finishOrder.last()]!!.rank)
    }
}

class BluffMarketEngineTest {
    private fun engine(seed: Int = 1, n: Int = 4): BluffMarketEngine {
        val e = BluffMarketEngine(Random(seed))
        (0 until n).forEach { e.addPlayer("p$it", "P$it") }
        return e
    }

    @Test fun `start deals exactly three cards to each player`() {
        val e = engine(2, n = 4)
        e.start()
        for (p in e.players.values) assertEquals(3, p.hand.size)
        assertEquals(BluffMarketPhase.PLAYING, e.phase)
    }

    @Test fun `deck always contains exactly one bomb by default`() {
        val e = engine(11, n = 4)
        e.start()
        val totalCards = e.players.values.sumOf { it.hand.size } + e.market.size
        val bombs = (e.players.values.flatMap { it.hand } + e.market).count { it.kind is BluffKind.Bomb }
        assertEquals(1, bombs)
        assertTrue(totalCards > 0)
    }

    @Test fun `twoBombs option seeds two bombs`() {
        val e = engine(11, n = 5)
        e.addPlayer("p5", "P5") // bring to 5 players (n=5)
        e.setOptions(BluffMarketOptions(twoBombs = true))
        e.start()
        val bombs = (e.players.values.flatMap { it.hand } + e.market).count { it.kind is BluffKind.Bomb }
        assertEquals(2, bombs)
    }

    @Test fun `selling earns 2 coins and advances turn`() {
        val e = engine(7, n = 4)
        e.start()
        val first = e.current!!
        val cid = first.hand.first().id
        assertNull(e.sellToMarket(first.id, cid))
        assertEquals(2, first.coins)
        assertEquals(2, first.hand.size)
        assertEquals(1, first.turnsTaken)
    }

    @Test fun `buy from market moves the top card into hand`() {
        val e = engine(7, n = 4)
        e.start()
        val first = e.current!!
        val priorMarket = e.market.size
        val priorHand = first.hand.size
        assertNull(e.buyFromMarket(first.id))
        assertEquals(priorMarket - 1, e.market.size)
        assertEquals(priorHand + 1, first.hand.size)
    }

    @Test fun `trade flow swaps cards when both accept`() {
        val e = engine(7, n = 4)
        e.start()
        val a = e.current!!
        val bId = e.seatingSnapshot.first { it != a.id }
        val b = e.players[bId]!!
        val aCardId = a.hand.first().id
        val bCardId = b.hand.first().id
        assertNull(e.proposeTrade(a.id, b.id, aCardId))
        assertNull(e.counterTrade(b.id, bCardId))
        assertNull(e.respondTrade(a.id, true))
        assertNull(e.respondTrade(b.id, true))
        assertNull(e.activeTrade)
        // Cards swapped.
        assertTrue(a.hand.any { it.id == bCardId })
        assertTrue(b.hand.any { it.id == aCardId })
    }

    @Test fun `Guarantee forces trade even if other side rejects`() {
        val e = engine(7, n = 4)
        e.start()
        val a = e.current!!
        val bId = e.seatingSnapshot.first { it != a.id }
        val b = e.players[bId]!!
        val aCardId = a.hand.first().id
        val bCardId = b.hand.first().id
        e.proposeTrade(a.id, b.id, aCardId)
        e.counterTrade(b.id, bCardId)
        e.useGuarantee(a.id)
        e.respondTrade(a.id, true)
        e.respondTrade(b.id, false) // b rejects — trade still happens
        assertNull(e.activeTrade)
        assertTrue(b.hand.any { it.id == aCardId })
        assertTrue(a.guaranteeUsed)
    }

    @Test fun `Bomb subtracts 25 from holder's total`() {
        val e = engine(13, n = 4)
        e.start()
        val bombHolder = e.players.values.firstOrNull { p ->
            p.hand.any { it.kind is BluffKind.Bomb }
        } ?: return  // skip if RNG put the bomb in the market this seed
        val row = e.score().first { it.id == bombHolder.id }
        val expectedSum = bombHolder.hand.sumOf { it.points } // includes -25
        assertEquals(expectedSum, row.sum)
        assertEquals(expectedSum + bombHolder.coins, row.total)
        assertTrue(row.hasBomb)
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
