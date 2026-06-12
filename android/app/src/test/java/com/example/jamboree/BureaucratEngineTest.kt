package com.example.jamboree

import com.example.jamboree.games.bureaucrat.BureaucratEngine
import com.example.jamboree.games.bureaucrat.BureaucratOptions
import com.example.jamboree.games.bureaucrat.BureaucratPhase
import com.example.jamboree.games.bureaucrat.KeywordContradictionDetector
import com.example.jamboree.games.bureaucrat.RoundEndReason
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BureaucratEngineTest {
    private fun engine(seed: Int = 1, n: Int = 3): BureaucratEngine {
        val e = BureaucratEngine(Random(seed))
        e.addPlayer("host", "Host", isHost = true)
        (1 until n).forEach { e.addPlayer("g$it", "G$it") }
        return e
    }

    @Test fun `needs three players to start`() {
        val e = BureaucratEngine(Random(1))
        e.addPlayer("a", "A"); e.addPlayer("b", "B")
        assertFalse(e.canStart)
        e.addPlayer("c", "C")
        assertTrue(e.canStart)
    }

    @Test fun `start assigns a bureaucrat a task and tokens`() {
        val e = engine(seed = 5, n = 4)
        e.start()
        assertEquals(BureaucratPhase.ARGUING, e.phase)
        assertNotNull(e.bureaucratId)
        assertNotNull(e.task)
        assertEquals(1, e.roundNumber)
        // Every citizen has the default token allotment; bureaucrat has none.
        assertEquals(3, e.citizens.size)
        for (c in e.citizens) assertEquals(2, e.tokensFor(c.id))
        assertEquals(0, e.tokensFor(e.bureaucratId!!))
    }

    @Test fun `only the bureaucrat can append denials`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val citizen = e.citizens.first().id
        assertFalse(e.addDenial(citizen, "Citizens cannot legislate."))
        assertTrue(e.addDenial(b, "Form 7B is required for all exemptions."))
        assertEquals(1, e.policyLog.size)
        assertFalse(e.policyLog[0].isRebuttal)
    }

    @Test fun `blank denials are rejected`() {
        val e = engine(n = 4); e.start()
        assertFalse(e.addDenial(e.bureaucratId!!, "   "))
        assertEquals(0, e.policyLog.size)
    }

    @Test fun `timed-out rebuttal hands the round and reward to the challenger`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val challenger = e.citizens.first().id
        e.addDenial(b, "Form 7B is required.")
        assertTrue(e.callLoophole(challenger))
        assertEquals(BureaucratPhase.REBUTTAL, e.phase)
        assertEquals(challenger, e.pendingChallenger)
        assertTrue(e.rebuttalTimedOut())
        assertEquals(BureaucratPhase.ROUND_OVER, e.phase)
        assertEquals(3, e.players[challenger]!!.score)   // LOOPHOLE_REWARD
        assertEquals(0, e.players[b]!!.score)
        assertEquals(RoundEndReason.LOOPHOLE_TIMEOUT, e.lastRound!!.reason)
        assertEquals(challenger, e.lastRound!!.challengerId)
    }

    @Test fun `contradicting rebuttal also wins the round for the challenger`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val challenger = e.citizens.first().id
        e.addDenial(b, "Form 7B is required.")
        e.callLoophole(challenger)
        assertTrue(e.submitRebuttal("Form 7B was discontinued.", contradicts = true))
        assertEquals(BureaucratPhase.ROUND_OVER, e.phase)
        assertEquals(RoundEndReason.LOOPHOLE_CONTRADICTION, e.lastRound!!.reason)
        assertEquals(3, e.players[challenger]!!.score)
    }

    @Test fun `successful rebuttal burns a token and penalises the challenger`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val challenger = e.citizens.first().id
        e.players[challenger]!!.score = 4
        e.addDenial(b, "Form 7B is required.")
        e.callLoophole(challenger)
        assertTrue(e.submitRebuttal("Exemptions use the modern Form 7C instead.", contradicts = false))
        assertEquals(BureaucratPhase.ARGUING, e.phase)
        assertEquals(1, e.tokensFor(challenger))         // 2 -> 1
        assertEquals(3, e.players[challenger]!!.score)   // 4 - FAIL_PENALTY
        assertNull(e.pendingChallenger)
        assertTrue(e.policyLog.last().isRebuttal)
    }

    @Test fun `score never goes negative on a failed challenge`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val challenger = e.citizens.first().id
        e.addDenial(b, "Form 7B is required.")
        e.callLoophole(challenger)
        e.submitRebuttal("Form 7C supersedes it.", contradicts = false)
        assertEquals(0, e.players[challenger]!!.score)
    }

    @Test fun `running every citizen out of tokens ends the round for the bureaucrat`() {
        val e = engine(n = 3); e.start()   // 2 citizens, 2 tokens each
        val b = e.bureaucratId!!
        e.addDenial(b, "Everything is denied.")
        // Burn all four tokens via failed challenges.
        var guard = 0
        while (e.phase == BureaucratPhase.ARGUING && guard++ < 20) {
            val withToken = e.citizens.firstOrNull { e.tokensFor(it.id) > 0 } ?: break
            e.callLoophole(withToken.id)
            e.submitRebuttal("Defended.", contradicts = false)
        }
        assertEquals(BureaucratPhase.ROUND_OVER, e.phase)
        assertEquals(RoundEndReason.TOKENS_EXHAUSTED, e.lastRound!!.reason)
        assertEquals(2, e.players[b]!!.score)            // SURVIVE_REWARD
    }

    @Test fun `host can survive the round directly`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        assertTrue(e.bureaucratSurvives())
        assertEquals(BureaucratPhase.ROUND_OVER, e.phase)
        assertEquals(2, e.players[b]!!.score)
        assertEquals(RoundEndReason.BUREAUCRAT_SURVIVED, e.lastRound!!.reason)
    }

    @Test fun `bureaucrat rotates each round`() {
        val e = engine(seed = 3, n = 3); e.start()
        val first = e.bureaucratId
        assertNotNull(e.nextBureaucratId())
        e.bureaucratSurvives()
        e.nextRound()
        assertEquals(BureaucratPhase.ARGUING, e.phase)
        assertEquals(2, e.roundNumber)
        assertTrue(e.bureaucratId != first, "bureaucrat should rotate")
    }

    @Test fun `reaching the target score ends the game`() {
        val e = engine(seed = 2, n = 3)
        e.setOptions(BureaucratOptions(targetScore = 2))
        e.start()
        val b1 = e.bureaucratId!!
        e.bureaucratSurvives()                       // +2 → at target
        assertEquals(BureaucratPhase.ROUND_OVER, e.phase)
        e.nextRound()                                // leader >= target ends it
        assertEquals(BureaucratPhase.GAME_OVER, e.phase)
        assertEquals(b1, e.winnerId)
        assertTrue(e.players[e.winnerId]!!.score >= 2)
    }

    @Test fun `cannot call a loophole with no tokens left`() {
        val e = engine(n = 3); e.start()
        val challenger = e.citizens.first().id
        e.addDenial(e.bureaucratId!!, "Denied.")
        e.callLoophole(challenger); e.submitRebuttal("a", contradicts = false)
        e.callLoophole(challenger); e.submitRebuttal("b", contradicts = false)
        assertEquals(0, e.tokensFor(challenger))
        assertFalse(e.callLoophole(challenger))
    }

    @Test fun `options are clamped to sane ranges`() {
        val e = engine(n = 3)
        e.setOptions(BureaucratOptions(targetScore = 999, challengeTokens = 0, rebuttalSeconds = 1))
        assertEquals(50, e.options.targetScore)
        assertEquals(1, e.options.challengeTokens)
        assertEquals(5, e.options.rebuttalSeconds)
    }

    @Test fun `rebuttalMode option clamps to type for unknown values`() {
        val e = engine(n = 3)
        e.setOptions(BureaucratOptions(rebuttalMode = "yell"))
        assertEquals("type", e.options.rebuttalMode)
    }

    @Test fun `the task never repeats the previous round`() {
        val e = engine(seed = 7, n = 3)
        e.setOptions(BureaucratOptions(targetScore = 50))   // keep the game going
        e.start()
        var prev = e.task
        repeat(30) {
            e.bureaucratSurvives()
            e.nextRound()
            assertEquals(BureaucratPhase.ARGUING, e.phase)
            assertNotNull(e.task)
            assertTrue(e.task != prev, "task repeated back-to-back: ${e.task}")
            prev = e.task
        }
    }
}

class KeywordContradictionDetectorTest {
    private val d = KeywordContradictionDetector()

    @Test fun `opposite polarity on a shared form code is a contradiction`() {
        val prior = listOf("Form 7B is required for all exemptions.")
        assertTrue(d.contradicts(prior, "Form 7B was discontinued and is no longer available."))
    }

    @Test fun `consistent rebuttal on the same subject is fine`() {
        val prior = listOf("Form 7B is required for all exemptions.")
        assertFalse(d.contradicts(prior, "Form 7B must be notarised as well."))
    }

    @Test fun `unrelated rebuttal is not a contradiction`() {
        val prior = listOf("Form 7B is required for all exemptions.")
        assertFalse(d.contradicts(prior, "Goldfish cannot hold property under maritime law."))
    }

    @Test fun `empty rebuttal is never a contradiction`() {
        assertFalse(d.contradicts(listOf("Anything is denied."), "   "))
    }

    @Test fun `polarity flip on a shared noun is caught`() {
        val prior = listOf("Permits are mandatory for indoor whistling.")
        assertTrue(d.contradicts(prior, "Permits are prohibited and cannot be issued."))
    }
}
