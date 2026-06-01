package com.example.jamboree

import com.example.jamboree.games.imposter.ImposterEngine
import com.example.jamboree.games.imposter.ImposterPhase
import com.example.jamboree.games.imposter.ImposterWinner
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Engine phase-logic coverage for Imposter — voting, vote resolution and
 * winner determination. Options-level behaviour lives in [GameOptionsTest].
 * The Swift engine is kept in lockstep, so this guards both platforms.
 */
class ImposterEngineTest {

    private fun started(seed: Int, ids: List<String>): ImposterEngine {
        val e = ImposterEngine(Random(seed))
        ids.forEach { e.addPlayer(it, it) }
        e.start()
        return e
    }

    @Test fun `needs at least three players to start`() {
        val e = ImposterEngine(Random(1))
        listOf("a", "b").forEach { e.addPlayer(it, it) }
        assertFalse(e.canStart)
        e.start()
        assertEquals(ImposterPhase.LOBBY, e.phase)
    }

    @Test fun `start enters playing with a category and secret word`() {
        val e = started(2, listOf("a", "b", "c", "d"))
        assertEquals(ImposterPhase.PLAYING, e.phase)
        assertTrue(e.category.isNotEmpty())
        assertTrue(e.secretWord.isNotEmpty())
    }

    @Test fun `voting only counts known players and resolves once everyone votes`() {
        val e = started(3, listOf("a", "b", "c", "d"))
        e.beginVoting()
        assertEquals(ImposterPhase.VOTING, e.phase)
        assertFalse(e.submitVote("ghost", "a"))   // unknown voter ignored
        assertFalse(e.submitVote("a", "ghost"))   // unknown target ignored
        assertFalse(e.submitVote("a", "b"))
        assertFalse(e.submitVote("b", "a"))
        assertFalse(e.submitVote("c", "a"))
        assertTrue(e.submitVote("d", "a"))         // last vote → table complete
    }

    @Test fun `town wins when the imposter is the unique most-voted`() {
        val e = started(4, listOf("a", "b", "c", "d"))
        val imposter = e.players.values.first { it.isImposter }.id
        e.beginVoting()
        // Everyone piles onto the imposter.
        e.players.keys.forEach { e.submitVote(it, imposter) }
        e.resolveVotes()
        assertEquals(imposter, e.mostVotedId)
        assertEquals(true, e.imposterCaught)
        assertEquals(ImposterWinner.TOWN, e.winner)
        assertEquals(ImposterPhase.RESULT, e.phase)
    }

    @Test fun `imposter wins when a townie is voted out`() {
        val e = started(5, listOf("a", "b", "c", "d"))
        val townie = e.players.values.first { !it.isImposter }.id
        e.beginVoting()
        e.players.keys.forEach { e.submitVote(it, townie) }
        e.resolveVotes()
        assertEquals(townie, e.mostVotedId)
        assertEquals(false, e.imposterCaught)
        assertEquals(ImposterWinner.IMPOSTER, e.winner)
    }

    @Test fun `a tie has no unique target and the imposter survives`() {
        val e = started(6, listOf("a", "b", "c", "d"))
        e.beginVoting()
        // Two votes for "a", two for "b" — a tie, nobody is ejected.
        e.submitVote("a", "b")
        e.submitVote("b", "a")
        e.submitVote("c", "a")
        e.submitVote("d", "b")
        e.resolveVotes()
        assertNull(e.mostVotedId)
        assertNull(e.imposterCaught)   // tri-state: no unique ejection
        assertEquals(ImposterWinner.IMPOSTER, e.winner)
    }

    @Test fun `reset returns to lobby and clears the round`() {
        val e = started(7, listOf("a", "b", "c", "d"))
        e.beginVoting()
        e.players.keys.forEach { e.submitVote(it, "a") }
        e.resolveVotes()
        e.reset()
        assertEquals(ImposterPhase.LOBBY, e.phase)
        assertTrue(e.imposterIds.isEmpty())
        assertNull(e.winner)
        assertNull(e.mostVotedId)
        assertTrue(e.votes.isEmpty())
        assertTrue(e.players.values.none { it.isImposter })
    }
}
