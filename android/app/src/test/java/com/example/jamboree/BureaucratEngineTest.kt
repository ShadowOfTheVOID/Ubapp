package com.example.jamboree

import com.example.jamboree.games.bureaucrat.BureaucratEngine
import com.example.jamboree.games.bureaucrat.BureaucratOptions
import com.example.jamboree.games.bureaucrat.BureaucratPhase
import com.example.jamboree.games.bureaucrat.KeywordContradictionDetector
import com.example.jamboree.games.bureaucrat.PolicyKind
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

    @Test fun `the round seeds the request as the first policy line`() {
        val e = engine(n = 4); e.start()
        assertEquals(1, e.policyLog.size)
        assertEquals(PolicyKind.REQUEST, e.policyLog[0].kind)
        assertEquals(e.task, e.policyLog[0].text)
    }

    @Test fun `only the bureaucrat can append denials`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val citizen = e.citizens.first().id
        assertFalse(e.addDenial(citizen, "Citizens cannot legislate."))
        assertTrue(e.addDenial(b, "Form 7B is required for all exemptions."))
        // policyLog is [request, denial].
        assertEquals(2, e.policyLog.size)
        assertEquals(PolicyKind.DENIAL, e.policyLog.last().kind)
        assertEquals(b, e.policyLog.last().authorId)
    }

    @Test fun `blank denials are rejected`() {
        val e = engine(n = 4); e.start()
        assertFalse(e.addDenial(e.bureaucratId!!, "   "))
        assertEquals(1, e.policyLog.size)   // request only
    }

    @Test fun `calling a loophole records the claim and needs a non-blank claim`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val challenger = e.citizens.first().id
        e.addDenial(b, "Goldfish cannot co-sign.")
        assertFalse(e.callLoophole(challenger, "   "))      // blank claim rejected
        assertEquals(BureaucratPhase.ARGUING, e.phase)
        assertEquals(2, e.tokensFor(challenger))            // no token spent
        assertTrue(e.callLoophole(challenger, "A goldfish is alive in law."))
        assertEquals(BureaucratPhase.REBUTTAL, e.phase)
        assertEquals(PolicyKind.CLAIM, e.policyLog.last().kind)
        assertEquals(challenger, e.policyLog.last().authorId)
    }

    @Test fun `timed-out rebuttal hands the round and reward to the challenger`() {
        val e = engine(n = 4); e.start()
        val b = e.bureaucratId!!
        val challenger = e.citizens.first().id
        e.addDenial(b, "Form 7B is required.")
        assertTrue(e.callLoophole(challenger, "I already filed Form 7B."))
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
        e.callLoophole(challenger, "I already filed Form 7B.")
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
        e.callLoophole(challenger, "I already filed Form 7B.")
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
        e.callLoophole(challenger, "I already filed Form 7B.")
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
            e.callLoophole(withToken.id, "Surely there is an exception.")
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
        e.callLoophole(challenger, "Try one"); e.submitRebuttal("a", contradicts = false)
        e.callLoophole(challenger, "Try two"); e.submitRebuttal("b", contradicts = false)
        assertEquals(0, e.tokensFor(challenger))
        assertFalse(e.callLoophole(challenger, "Try three"))
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

    // --- Table-vote judging mode ---------------------------------------------

    private fun votingEngine(n: Int = 4): Triple<BureaucratEngine, String, String> {
        val e = engine(n = n)
        e.setOptions(BureaucratOptions(judging = "vote"))
        e.start()
        val b = e.bureaucratId!!
        val challenger = e.citizens.first().id
        e.addDenial(b, "Everything is denied.")
        e.callLoophole(challenger, "Surely an exception applies.")
        assertEquals(BureaucratPhase.REBUTTAL, e.phase)
        // In vote mode the detector verdict is ignored — the table rules.
        assertTrue(e.submitRebuttal("My binding defence.", contradicts = true))
        assertEquals(BureaucratPhase.VOTING, e.phase)
        return Triple(e, b, challenger)
    }

    @Test fun `vote mode sends a submitted rebuttal to the table`() {
        val (e, _, _) = votingEngine()
        // The bureaucrat and challenger are excluded; everyone else may vote.
        assertEquals(2, e.voters.size)
        assertTrue(e.policyLog.last().isRebuttal)
    }

    @Test fun `neither bureaucrat nor challenger may vote`() {
        val (e, b, challenger) = votingEngine()
        assertFalse(e.castVote(b, true))
        assertFalse(e.castVote(challenger, true))
        assertTrue(e.votes.isEmpty())
    }

    @Test fun `a table majority for the loophole hands the round to the challenger`() {
        val (e, _, challenger) = votingEngine()
        val voters = e.voters.map { it.id }
        e.castVote(voters[0], true)
        assertEquals(BureaucratPhase.VOTING, e.phase)   // still collecting
        e.castVote(voters[1], true)                     // last ballot auto-tallies
        assertEquals(BureaucratPhase.ROUND_OVER, e.phase)
        assertEquals(RoundEndReason.LOOPHOLE_VOTE, e.lastRound!!.reason)
        assertEquals(challenger, e.lastRound!!.challengerId)
        assertEquals(3, e.players[challenger]!!.score)  // LOOPHOLE_REWARD
    }

    @Test fun `the table upholding the denial burns a token and penalises the challenger`() {
        val (e, _, challenger) = votingEngine()
        e.players[challenger]!!.score = 4
        val voters = e.voters.map { it.id }
        e.castVote(voters[0], false); e.castVote(voters[1], false)
        assertEquals(BureaucratPhase.ARGUING, e.phase)
        assertEquals(1, e.tokensFor(challenger))        // 2 -> 1
        assertEquals(3, e.players[challenger]!!.score)  // 4 - FAIL_PENALTY
        assertNull(e.pendingChallenger)
    }

    @Test fun `a tied table vote favours the bureaucrat`() {
        val (e, _, _) = votingEngine()
        val voters = e.voters.map { it.id }
        e.castVote(voters[0], true); e.castVote(voters[1], false)
        assertEquals(BureaucratPhase.ARGUING, e.phase)  // 1 of 2 is not a majority
    }

    @Test fun `a clear majority carries even when not everyone has voted`() {
        // 5 players → 3 eligible voters; two "stands" already clear the bar.
        val (e, _, _) = votingEngine(n = 5)
        assertEquals(3, e.voters.size)
        val voters = e.voters.map { it.id }
        e.castVote(voters[0], true); e.castVote(voters[1], true)
        // forceTally with the third ballot missing still overturns: 2 of 3.
        assertTrue(e.forceTally())
        assertEquals(BureaucratPhase.ROUND_OVER, e.phase)
        assertEquals(RoundEndReason.LOOPHOLE_VOTE, e.lastRound!!.reason)
    }

    @Test fun `force-tally with no ballots lets the denial stand`() {
        val (e, _, challenger) = votingEngine()
        assertTrue(e.forceTally())
        assertEquals(BureaucratPhase.ARGUING, e.phase)
        assertEquals(1, e.tokensFor(challenger))        // treated as a failed challenge
    }

    @Test fun `judging option clamps to nli for unknown values`() {
        val e = engine(n = 3)
        e.setOptions(BureaucratOptions(judging = "telepathy"))
        assertEquals("nli", e.options.judging)
        e.setOptions(BureaucratOptions(judging = "vote"))
        assertEquals("vote", e.options.judging)
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

    @Test fun `judge points at the exact clashing line`() {
        val prior = listOf(
            "Indoor whistling needs a permit.",
            "Form 7B is required for all exemptions.",
        )
        val v = d.judge(prior, "Form 7B was discontinued and is no longer available.")
        assertTrue(v.contradicts)
        assertEquals(1, v.priorIndex)            // the Form 7B line, not the whistling one
        assertEquals("contradiction", v.label)
    }

    @Test fun `judge reports no contradiction for a consistent rebuttal`() {
        val prior = listOf("Form 7B is required for all exemptions.")
        val v = d.judge(prior, "Form 7B must be notarised as well.")
        assertFalse(v.contradicts)
    }
}
