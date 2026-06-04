package com.example.jamboree

import com.example.jamboree.tutorials.TutorialVote
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Coverage for the shared yes/no tutorial vote. Kept in lockstep with the
 * Swift `TutorialVote`. Focuses on the threshold (ties skip the tutorial) and
 * the mid-vote `removeVoter` paths, which the per-game servers rely on.
 */
class TutorialVoteTest {

    @Test fun `unanimous yes shows the tutorial`() {
        val v = TutorialVote()
        v.open(listOf("a", "b"))
        assertFalse(v.submit("a", true))   // not everyone has voted yet
        assertTrue(v.submit("b", true))    // last vote finalizes
        assertFalse(v.isOpen)
        assertEquals(true, v.result)
    }

    @Test fun `a tie resolves to no`() {
        val v = TutorialVote()
        v.open(listOf("a", "b"))
        v.submit("a", true)
        v.submit("b", false)
        assertEquals(false, v.result)      // strict majority — tie skips it
    }

    @Test fun `non-eligible and post-close votes are rejected`() {
        val v = TutorialVote()
        v.open(listOf("a", "b"))
        assertFalse(v.submit("intruder", true))   // never eligible
        v.submit("a", true); v.submit("b", true)  // closes the vote
        assertFalse(v.submit("a", false))         // vote already closed
        assertEquals(true, v.result)
    }

    @Test fun `re-voting overwrites and never exceeds the eligible count`() {
        val v = TutorialVote()
        v.open(listOf("a", "b"))
        v.submit("a", true)
        v.submit("a", false)               // same voter changes their mind
        assertEquals(0, v.yesCount)
        assertEquals(1, v.noCount)
        assertFalse(v.hasResult)           // b still hasn't voted
    }

    @Test fun `removing the last unvoted player finalizes the vote`() {
        val v = TutorialVote()
        v.open(listOf("a", "b"))
        v.submit("a", true)                // a voted yes, b hasn't
        v.removeVoter("b")                 // now everyone remaining has voted
        assertFalse(v.isOpen)
        assertEquals(true, v.result)
    }

    @Test fun `removing every voter resets to a closed, result-less vote`() {
        val v = TutorialVote()
        v.open(listOf("a", "b"))
        v.removeVoter("a")
        v.removeVoter("b")
        assertFalse(v.isOpen)
        assertNull(v.result)
        assertEquals(0, v.eligibleCount)
    }
}
