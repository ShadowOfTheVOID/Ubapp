package com.example.jamboree

import com.example.jamboree.stats.SeriesScore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Regression net for the pure [SeriesScore] tally. The Swift SeriesScore is
 * kept byte-equivalent, so this guards both platforms.
 */
class SeriesScoreTest {

    @Test fun `starts empty`() {
        val s = SeriesScore()
        assertTrue(s.isEmpty)
        assertEquals(0, s.rounds)
        assertTrue(s.scores.isEmpty())
    }

    @Test fun `records accumulate per outcome`() {
        val s = SeriesScore()
        s.record("town"); s.record("mafia"); s.record("town")
        assertEquals(3, s.rounds)
        assertEquals(2, s.scores["town"])
        assertEquals(1, s.scores["mafia"])
        assertFalse(s.isEmpty)
    }

    @Test fun `reset clears the tally`() {
        val s = SeriesScore()
        s.record("red"); s.record("blue")
        s.reset()
        assertEquals(0, s.rounds)
        assertTrue(s.scores.isEmpty())
        assertTrue(s.isEmpty)
    }

    @Test fun `insertion order is preserved`() {
        val s = SeriesScore()
        s.record("blue"); s.record("red"); s.record("blue")
        assertEquals(listOf("blue", "red"), s.scores.keys.toList())
    }
}
