package com.example.ubapp

import com.example.ubapp.games.codenames.CardKind
import com.example.ubapp.games.codenames.CodenamesEngine
import com.example.ubapp.games.codenames.CodenamesOptions
import com.example.ubapp.games.codenames.CodenamesPhase
import com.example.ubapp.games.codenames.Team
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Engine phase-logic coverage for Codenames — board generation, turn passing,
 * the assassin loss and the all-words win. Board-size/assassin option clamping
 * lives in [GameOptionsTest]. Kept in lockstep with the Swift engine.
 */
class CodenamesEngineTest {

    private fun started(seed: Int, size: Int = 25, assassins: Int = 1): CodenamesEngine {
        val e = CodenamesEngine(Random(seed))
        listOf("r1", "r2", "b1", "b2").forEach { e.addPlayer(it, it) }
        e.setTeam("r1", Team.RED); e.setTeam("r2", Team.RED)
        e.setTeam("b1", Team.BLUE); e.setTeam("b2", Team.BLUE)
        e.setSpymaster("r1", true); e.setSpymaster("b1", true)
        e.setOptions(CodenamesOptions(boardSize = size, assassinCount = assassins))
        e.start()
        return e
    }

    private fun spymaster(e: CodenamesEngine) = if (e.currentTeam == Team.RED) "r1" else "b1"
    private fun guesser(e: CodenamesEngine) = if (e.currentTeam == Team.RED) "r2" else "b2"

    @Test fun `cannot start without two-per-team and a spymaster each`() {
        val e = CodenamesEngine(Random(1))
        listOf("r1", "r2", "b1", "b2").forEach { e.addPlayer(it, it) }
        e.setTeam("r1", Team.RED); e.setTeam("r2", Team.RED)
        e.setTeam("b1", Team.BLUE); e.setTeam("b2", Team.BLUE)
        assertFalse(e.canStart)              // no spymasters yet
        e.setSpymaster("r1", true)
        assertFalse(e.canStart)              // blue still missing one
        e.setSpymaster("b1", true)
        assertTrue(e.canStart)
    }

    @Test fun `default board has 25 cards, one assassin, seven neutrals and a 9-8 split`() {
        val e = started(2)
        assertEquals(CodenamesPhase.PLAYING, e.phase)
        assertEquals(25, e.board.size)
        assertEquals(1, e.board.count { it.kind == CardKind.ASSASSIN })
        assertEquals(7, e.board.count { it.kind == CardKind.NEUTRAL })
        val reds = e.board.count { it.kind == CardKind.RED }
        val blues = e.board.count { it.kind == CardKind.BLUE }
        assertEquals(17, reds + blues)
        // Starting team gets the extra card: 9 vs 8.
        val starterCards = if (e.startingTeam == Team.RED) reds else blues
        assertEquals(9, starterCards)
    }

    @Test fun `guessing a neutral passes the turn to the other team`() {
        val e = started(3)
        val before = e.currentTeam
        e.submitClue(spymaster(e), "clue", 1)
        val neutral = e.board.indexOfFirst { it.kind == CardKind.NEUTRAL }
        e.guess(guesser(e), neutral)
        assertEquals(before.other, e.currentTeam)
        assertNull(e.currentClue)
    }

    @Test fun `hitting the assassin instantly loses for the guessing team`() {
        val e = started(4)
        val losing = e.currentTeam
        e.submitClue(spymaster(e), "clue", 1)
        val assassin = e.board.indexOfFirst { it.kind == CardKind.ASSASSIN }
        e.guess(guesser(e), assassin)
        assertEquals(CodenamesPhase.GAME_OVER, e.phase)
        assertEquals(losing.other, e.winner)
    }

    @Test fun `revealing all of your words wins the game`() {
        val e = started(5)
        val team = e.currentTeam
        val kind = if (team == Team.RED) CardKind.RED else CardKind.BLUE
        val indices = e.board.indices.filter { e.board[it].kind == kind }
        // Generous clue number so the whole team set can be cleared in one turn.
        e.submitClue(spymaster(e), "clue", indices.size)
        for (i in indices) e.guess(guesser(e), i)
        assertEquals(CodenamesPhase.GAME_OVER, e.phase)
        assertEquals(team, e.winner)
        assertEquals(0, e.cardsLeftFor(team))
    }

    @Test fun `sixteen-card board keeps four neutrals and the requested assassins`() {
        val e = started(6, size = 16, assassins = 2)
        assertEquals(16, e.board.size)
        assertEquals(2, e.board.count { it.kind == CardKind.ASSASSIN })
        assertEquals(4, e.board.count { it.kind == CardKind.NEUTRAL })
    }

    @Test fun `reset clears the board and returns to lobby`() {
        val e = started(7)
        e.reset()
        assertEquals(CodenamesPhase.LOBBY, e.phase)
        assertTrue(e.board.isEmpty())
        assertNull(e.winner)
    }
}
