package com.example.ubapp

import com.example.ubapp.games.secrethitler.SecretHitlerEngine
import com.example.ubapp.games.secrethitler.SecretHitlerPhase
import com.example.ubapp.games.secrethitler.SecretHitlerPolicy
import com.example.ubapp.games.secrethitler.SecretHitlerRole
import com.example.ubapp.games.secrethitler.SecretHitlerWinReason
import com.example.ubapp.games.secrethitler.SecretHitlerWinner
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SecretHitlerEngineTest {
    @Test fun `cannot start with fewer than 5 players`() {
        val e = SecretHitlerEngine()
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        assertFalse(e.canStart)
        e.start()
        assertEquals(SecretHitlerPhase.LOBBY, e.phase)
    }

    @Test fun `5 player setup gives 3 liberals 1 fascist 1 hitler`() {
        val e = engineWith(5, Random(42))
        val roles = e.players.values.groupingBy { it.role!! }.eachCount()
        assertEquals(3, roles[SecretHitlerRole.LIBERAL])
        assertEquals(1, roles[SecretHitlerRole.FASCIST])
        assertEquals(1, roles[SecretHitlerRole.HITLER])
        assertEquals(SecretHitlerPhase.NOMINATION, e.phase)
    }

    @Test fun `9 player setup gives 5 liberals 3 fascists 1 hitler`() {
        val e = engineWith(9, Random(7))
        val roles = e.players.values.groupingBy { it.role!! }.eachCount()
        assertEquals(5, roles[SecretHitlerRole.LIBERAL])
        assertEquals(3, roles[SecretHitlerRole.FASCIST])
        assertEquals(1, roles[SecretHitlerRole.HITLER])
    }

    @Test fun `hitler knows fascists in 5p game but not in 7p`() {
        val e5 = engineWith(5, Random(1))
        val hitler5 = e5.players.values.first { it.role == SecretHitlerRole.HITLER }
        assertTrue(e5.knownAllies(hitler5.id).isNotEmpty(),
                   "5p Hitler should know the single fascist")

        val e7 = engineWith(7, Random(1))
        val hitler7 = e7.players.values.first { it.role == SecretHitlerRole.HITLER }
        assertEquals(emptyList(), e7.knownAllies(hitler7.id),
                     "7p Hitler should not know fascists")
    }

    @Test fun `failed election advances the tracker and rotates president`() {
        val e = engineWith(5, Random(3))
        val pres1 = e.presidentId!!
        val nominee = e.eligibleChancellorNominees().first().id
        assertTrue(e.nominateChancellor(nominee))
        // Everyone votes Nein.
        for (p in e.alive) e.submitVote(p.id, false)
        e.resolveElection()
        assertEquals(1, e.electionTracker)
        assertEquals(SecretHitlerPhase.NOMINATION, e.phase)
        assertTrue(e.presidentId != pres1, "President should rotate after failed vote")
    }

    @Test fun `three failed elections trigger chaos and reset the tracker`() {
        val e = engineWith(5, Random(9))
        repeat(3) {
            val target = e.eligibleChancellorNominees().first().id
            e.nominateChancellor(target)
            for (p in e.alive) e.submitVote(p.id, false)
            e.resolveElection()
        }
        // Chaos enacts top policy. Tracker resets.
        assertEquals(0, e.electionTracker)
        assertEquals(1, e.liberalPolicies + e.fascistPolicies)
        assertEquals(SecretHitlerPhase.NOMINATION, e.phase)
    }

    @Test fun `legislative flow enacts a liberal policy`() {
        val e = engineWith(5, Random(2))
        // Stack the deck so the first three drawn are all liberal.
        val liberals = MutableList(6) { SecretHitlerPolicy.LIBERAL }
        val fascists = MutableList(11) { SecretHitlerPolicy.FASCIST }
        forceDeck(e, liberals + fascists)

        val nominee = e.eligibleChancellorNominees().first().id
        e.nominateChancellor(nominee)
        for (p in e.alive) e.submitVote(p.id, true)
        e.resolveElection()
        assertEquals(SecretHitlerPhase.PRESIDENT_DISCARD, e.phase)
        assertTrue(e.presidentDiscard(0))
        assertEquals(SecretHitlerPhase.CHANCELLOR_ENACT, e.phase)
        assertTrue(e.chancellorEnact(0))
        assertEquals(1, e.liberalPolicies)
        assertEquals(0, e.fascistPolicies)
        assertEquals(SecretHitlerPhase.NOMINATION, e.phase)
    }

    @Test fun `hitler elected chancellor after 3 fascist policies wins for fascists`() {
        val e = engineWith(5, Random(0))
        // Force 3 fascist policies on the board and pick a chancellor who is Hitler.
        forceFascistPolicies(e, 3)
        val hitler = e.players.values.first { it.role == SecretHitlerRole.HITLER }
        // Force president to NOT be Hitler so nomination is legal.
        val nonHitler = e.seatOrder.first { e.players[it]?.role != SecretHitlerRole.HITLER }
        forcePresident(e, nonHitler)
        e.nominateChancellor(hitler.id)
        for (p in e.alive) e.submitVote(p.id, true)
        e.resolveElection()
        assertEquals(SecretHitlerPhase.GAME_OVER, e.phase)
        assertEquals(SecretHitlerWinner.FASCIST, e.winner)
        assertEquals(SecretHitlerWinReason.HITLER_ELECTED_CHANCELLOR, e.winReason)
    }

    @Test fun `executing hitler wins for liberals`() {
        val e = engineWith(7, Random(5))
        forceFascistPolicies(e, 4) // not enough to be over, but puts us in execution range
        // Drive to execution phase manually by forcing it.
        forceExecutionPhase(e)
        val hitler = e.players.values.first { it.role == SecretHitlerRole.HITLER }
        // Make sure president isn't Hitler.
        if (e.presidentId == hitler.id) {
            forcePresident(e, e.seatOrder.first { it != hitler.id && e.players[it]?.alive == true })
        }
        assertTrue(e.executePlayer(hitler.id))
        assertEquals(SecretHitlerPhase.GAME_OVER, e.phase)
        assertEquals(SecretHitlerWinner.LIBERAL, e.winner)
        assertEquals(SecretHitlerWinReason.HITLER_EXECUTED, e.winReason)
    }

    @Test fun `term limits exclude previous chancellor`() {
        val e = engineWith(7, Random(11))
        val firstNominee = e.eligibleChancellorNominees().first().id
        e.nominateChancellor(firstNominee)
        for (p in e.alive) e.submitVote(p.id, true)
        e.resolveElection()
        // Make sure we got into legislative — skip rest of the round.
        assertEquals(SecretHitlerPhase.PRESIDENT_DISCARD, e.phase)
        e.presidentDiscard(0); e.chancellorEnact(0)
        // Now we're at next nomination. The previous chancellor should be ineligible.
        assertEquals(SecretHitlerPhase.NOMINATION, e.phase)
        val eligibleIds = e.eligibleChancellorNominees().map { it.id }
        assertFalse(firstNominee in eligibleIds, "Previous chancellor stays term-limited")
    }

    // --- Helpers ---------------------------------------------------------

    private fun engineWith(n: Int, rng: Random): SecretHitlerEngine {
        val e = SecretHitlerEngine(rng)
        for (i in 1..n) e.addPlayer("p$i", "P$i")
        e.start()
        assertNotNull(e.presidentId)
        return e
    }

    /** Replaces the deck with a deterministic ordering (top of deck first). */
    private fun forceDeck(e: SecretHitlerEngine, deck: List<SecretHitlerPolicy>) {
        e.drawPile.clear(); e.drawPile.addAll(deck)
        e.discardPile.clear()
    }

    private fun forceFascistPolicies(e: SecretHitlerEngine, n: Int) {
        val field = SecretHitlerEngine::class.java.getDeclaredField("fascistPolicies")
        field.isAccessible = true
        field.setInt(e, n)
    }

    private fun forcePresident(e: SecretHitlerEngine, id: String) {
        val field = SecretHitlerEngine::class.java.getDeclaredField("presidentId")
        field.isAccessible = true
        field.set(e, id)
    }

    private fun forceExecutionPhase(e: SecretHitlerEngine) {
        val field = SecretHitlerEngine::class.java.getDeclaredField("phase")
        field.isAccessible = true
        field.set(e, SecretHitlerPhase.EXECUTION)
    }
}
