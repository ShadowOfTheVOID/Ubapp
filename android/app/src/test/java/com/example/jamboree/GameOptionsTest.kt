package com.example.ubapp

import com.example.ubapp.games.codenames.CardKind
import com.example.ubapp.games.codenames.CodenamesEngine
import com.example.ubapp.games.codenames.CodenamesOptions
import com.example.ubapp.games.codenames.Team
import com.example.ubapp.games.crazyeights.Card
import com.example.ubapp.games.crazyeights.CrazyEightsEngine
import com.example.ubapp.games.crazyeights.CrazyEightsOptions
import com.example.ubapp.games.crazyeights.CrazyEightsPhase
import com.example.ubapp.games.crazyeights.Suit
import com.example.ubapp.games.imposter.ImposterEngine
import com.example.ubapp.games.imposter.ImposterOptions
import com.example.ubapp.games.imposter.ImposterWords
import com.example.ubapp.games.mafia.MafiaEngine
import com.example.ubapp.games.mafia.MafiaOptions
import com.example.ubapp.games.mafia.MafiaRole
import com.example.ubapp.games.werewolf.WerewolfEngine
import com.example.ubapp.games.werewolf.WerewolfOptions
import com.example.ubapp.games.werewolf.WerewolfRole
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GameOptionsTest {

    // --- Imposter ---

    @Test fun `imposter defaults to single imposter`() {
        val e = ImposterEngine(Random(1))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.start()
        assertEquals(1, e.imposterIds.size)
        assertEquals(1, e.players.values.count { it.isImposter })
        // Default: no decoy word, category is one of the built-ins.
        assertNull(e.players.values.first { it.isImposter }.decoyWord)
        assertTrue(e.category in ImposterWords.categories.keys)
    }

    @Test fun `imposter count two assigns exactly two imposters`() {
        val e = ImposterEngine(Random(2))
        listOf("a", "b", "c", "d", "e").forEach { e.addPlayer(it, it) }
        e.setOptions(ImposterOptions(imposterCount = 2))
        e.start()
        assertEquals(2, e.imposterIds.size)
        assertEquals(2, e.players.values.count { it.isImposter })
    }

    @Test fun `imposter count clamps to leave at least one villager`() {
        val e = ImposterEngine(Random(3))
        listOf("a", "b", "c").forEach { e.addPlayer(it, it) }
        e.setOptions(ImposterOptions(imposterCount = 99))
        assertEquals(2, e.options.imposterCount) // max = 3 - 1 = 2
        e.start()
        assertEquals(2, e.imposterIds.size)
    }

    @Test fun `imposter mixed pool uses Mixed category and any word`() {
        val e = ImposterEngine(Random(4))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.setOptions(ImposterOptions(mixedPool = true))
        e.start()
        assertEquals("Mixed", e.category)
        val allWords = ImposterWords.categories.values.flatten()
        assertTrue(e.secretWord in allWords)
    }

    @Test fun `imposter decoy word differs from secret`() {
        val e = ImposterEngine(Random(5))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.setOptions(ImposterOptions(decoyWord = true))
        e.start()
        val imp = e.players.values.first { it.isImposter }
        assertNotNull(imp.decoyWord)
        assertFalse(imp.decoyWord == e.secretWord)
    }

    @Test fun `imposter picks a first player and direction on start`() {
        val e = ImposterEngine(Random(6))
        val ids = listOf("a", "b", "c", "d")
        ids.forEach { e.addPlayer(it, it) }
        e.start()
        assertNotNull(e.firstPlayerId)
        assertTrue(e.firstPlayerId in ids)
        e.reset()
        assertNull(e.firstPlayerId)
        assertTrue(e.clockwise)
    }

    @Test fun `imposter does not repeat the same line-up two rounds in a row`() {
        val e = ImposterEngine(Random(7))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        var prev: Set<String>? = null
        repeat(40) {
            e.start()
            val now = e.imposterIds
            assertNotEquals(prev, now)
            prev = now
            e.reset()
        }
    }

    // --- Mafia ---

    @Test fun `mafia defaults match formula`() {
        val e = MafiaEngine(Random(10))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.start()
        val mafiaCount = e.players.values.count { it.role == MafiaRole.MAFIA }
        val doctorCount = e.players.values.count { it.role == MafiaRole.DOCTOR }
        assertEquals(1, mafiaCount)
        assertEquals(1, doctorCount)
    }

    @Test fun `mafia disabled doctor produces zero doctors`() {
        val e = MafiaEngine(Random(11))
        listOf("a", "b", "c", "d", "e").forEach { e.addPlayer(it, it) }
        e.setOptions(MafiaOptions(doctorEnabled = false))
        e.start()
        assertEquals(0, e.players.values.count { it.role == MafiaRole.DOCTOR })
        assertEquals(1, e.players.values.count { it.role == MafiaRole.MAFIA })
        // Night should resolve without doctor input.
        val mafia = e.players.values.first { it.role == MafiaRole.MAFIA }
        val villager = e.players.values.first { it.role == MafiaRole.VILLAGER }
        assertTrue(e.submitMafiaVote(mafia.id, villager.id), "ready when no doctor exists")
    }

    @Test fun `mafia explicit count overrides formula`() {
        val e = MafiaEngine(Random(12))
        listOf("a", "b", "c", "d", "e", "f").forEach { e.addPlayer(it, it) }
        e.setOptions(MafiaOptions(mafiaCount = 3))
        e.start()
        assertEquals(3, e.players.values.count { it.role == MafiaRole.MAFIA })
    }

    // --- Werewolf ---

    @Test fun `werewolf disabled seer and hunter produces wolves vs villagers`() {
        val e = WerewolfEngine(Random(20))
        listOf("a", "b", "c", "d", "e", "f").forEach { e.addPlayer(it, it) }
        e.setOptions(WerewolfOptions(seerEnabled = false, hunterEnabled = false))
        e.start()
        assertEquals(0, e.players.values.count { it.role == WerewolfRole.SEER })
        assertEquals(0, e.players.values.count { it.role == WerewolfRole.HUNTER })
        assertTrue(e.players.values.count { it.role == WerewolfRole.WEREWOLF } >= 1)
    }

    @Test fun `werewolf explicit wolf count`() {
        val e = WerewolfEngine(Random(21))
        listOf("a", "b", "c", "d", "e", "f", "g").forEach { e.addPlayer(it, it) }
        e.setOptions(WerewolfOptions(wolfCount = 3))
        e.start()
        assertEquals(3, e.players.values.count { it.role == WerewolfRole.WEREWOLF })
    }

    // --- Codenames ---

    @Test fun `codenames sixteen card board has expected counts`() {
        val e = CodenamesEngine(Random(30))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.setTeam("a", Team.RED); e.setTeam("b", Team.RED)
        e.setTeam("c", Team.BLUE); e.setTeam("d", Team.BLUE)
        e.setSpymaster("a", true); e.setSpymaster("c", true)
        e.setOptions(CodenamesOptions(boardSize = 16, assassinCount = 1))
        e.start()
        assertEquals(16, e.board.size)
        val assassins = e.board.count { it.kind == CardKind.ASSASSIN }
        assertEquals(1, assassins)
        val reds = e.board.count { it.kind == CardKind.RED }
        val blues = e.board.count { it.kind == CardKind.BLUE }
        // Starting team gets ceil(teamCards/2) — total team cards = 16 - 4 neutrals - 1 = 11.
        assertEquals(11, reds + blues)
    }

    @Test fun `codenames extra assassin reduces team cards`() {
        val e = CodenamesEngine(Random(31))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.setTeam("a", Team.RED); e.setTeam("b", Team.RED)
        e.setTeam("c", Team.BLUE); e.setTeam("d", Team.BLUE)
        e.setSpymaster("a", true); e.setSpymaster("c", true)
        e.setOptions(CodenamesOptions(boardSize = 25, assassinCount = 2))
        e.start()
        assertEquals(25, e.board.size)
        assertEquals(2, e.board.count { it.kind == CardKind.ASSASSIN })
    }

    @Test fun `codenames rejects disallowed board size`() {
        val e = CodenamesEngine(Random(32))
        e.setOptions(CodenamesOptions(boardSize = 7))
        assertEquals(25, e.options.boardSize)
    }

    // --- Crazy Eights ---

    @Test fun `crazy eights jacks skip when enabled`() {
        val e = CrazyEightsEngine(Random(40))
        listOf("a", "b", "c").forEach { e.addPlayer(it, it) }
        e.setOptions(CrazyEightsOptions(jackSkips = true))
        e.start()
        // Engine guarantees currentIndex = 0 after start.
        for (p in e.players.values) p.hand.clear()
        e.discardPile.clear(); e.discardPile.add(Card(Suit.SPADES, 7))
        e.activeSuit = null
        val current = e.current!!
        current.hand.add(Card(Suit.SPADES, 11))
        current.hand.add(Card(Suit.CLUBS, 3))   // spare so the play doesn't empty the hand (= win)
        e.playCard(current.id, Card(Suit.SPADES, 11))
        // Jack-skip: 1 normal advance + 1 skip = currentIndex moves by 2.
        assertEquals(2, e.currentIndex)
    }

    @Test fun `crazy eights jacks do not skip when disabled`() {
        val e = CrazyEightsEngine(Random(40))
        listOf("a", "b", "c").forEach { e.addPlayer(it, it) }
        // Default options — jacks behave like any other card.
        e.start()
        for (p in e.players.values) p.hand.clear()
        e.discardPile.clear(); e.discardPile.add(Card(Suit.SPADES, 7))
        e.activeSuit = null
        val current = e.current!!
        current.hand.add(Card(Suit.SPADES, 11))
        current.hand.add(Card(Suit.CLUBS, 3))   // spare so the play doesn't empty the hand (= win)
        e.playCard(current.id, Card(Suit.SPADES, 11))
        assertEquals(1, e.currentIndex)
    }

    @Test fun `crazy eights queens reverse direction`() {
        val e = CrazyEightsEngine(Random(41))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.setOptions(CrazyEightsOptions(queenReverses = true))
        e.start()
        for (p in e.players.values) p.hand.clear()
        e.discardPile.clear(); e.discardPile.add(Card(Suit.HEARTS, 7))
        e.activeSuit = null
        val current = e.current!!
        current.hand.add(Card(Suit.HEARTS, 12))
        current.hand.add(Card(Suit.CLUBS, 3))   // spare so the play doesn't empty the hand (= win)
        e.playCard(current.id, Card(Suit.HEARTS, 12))
        // Queen reverses, then advances by direction=-1 from currentIndex=0.
        // (0 + -1) mod 4 = 3.
        assertEquals(3, e.currentIndex)
    }

    @Test fun `crazy eights custom hand size`() {
        val e = CrazyEightsEngine(Random(42))
        listOf("a", "b", "c").forEach { e.addPlayer(it, it) }
        e.setOptions(CrazyEightsOptions(startingHandSize = 4))
        e.start()
        for (p in e.players.values) assertEquals(4, p.hand.size)
    }

    @Test fun `crazy eights twos force the next player to draw two and skip`() {
        val e = CrazyEightsEngine(Random(7))
        listOf("a", "b", "c").forEach { e.addPlayer(it, it) }
        e.setOptions(CrazyEightsOptions(twosDrawTwo = true))
        e.start()
        for (p in e.players.values) p.hand.clear()
        e.discardPile.clear(); e.discardPile.add(Card(Suit.SPADES, 7))
        e.activeSuit = null
        val current = e.current!!
        current.hand.add(Card(Suit.SPADES, 2))   // matches suit, is a 2
        current.hand.add(Card(Suit.CLUBS, 3))    // spare so the play doesn't win
        assertNull(e.playCard(current.id, Card(Suit.SPADES, 2)))
        // Victim drew two and was skipped: index advances by 2.
        assertEquals(2, e.currentIndex)
        assertEquals(CrazyEightsPhase.PLAYING, e.phase)
    }

    @Test fun `crazy eights twos are inert when the option is off`() {
        val e = CrazyEightsEngine(Random(7))
        listOf("a", "b", "c").forEach { e.addPlayer(it, it) }
        e.start()
        for (p in e.players.values) p.hand.clear()
        e.discardPile.clear(); e.discardPile.add(Card(Suit.SPADES, 7))
        e.activeSuit = null
        val current = e.current!!
        current.hand.add(Card(Suit.SPADES, 2))
        current.hand.add(Card(Suit.CLUBS, 3))
        e.playCard(current.id, Card(Suit.SPADES, 2))
        assertEquals(1, e.currentIndex)   // normal single advance, no draw
    }
}
