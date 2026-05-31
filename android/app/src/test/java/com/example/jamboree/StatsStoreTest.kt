package com.example.jamboree

import com.example.jamboree.stats.StatsData
import com.example.jamboree.stats.StatsStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Regression net for the pure [StatsStore.applyRecord] aggregation. The Swift
 * `StatsStore.apply` is kept byte-equivalent, so this also guards iOS.
 */
class StatsStoreTest {

    @Test fun firstRecordCreatesGameStat() {
        val d = StatsStore.applyRecord(StatsData(), "mafia", listOf("Al", "Bo"), "town", 1000)
        val s = d.games["mafia"]!!
        assertEquals(1, s.playCount)
        assertEquals(1, s.outcomes["town"])
        assertEquals(1, d.recent.size)
        assertEquals("town", d.recent[0].outcome)
        assertEquals(listOf("Al", "Bo"), d.recent[0].players)
        assertEquals(1000L, d.recent[0].timestamp)
    }

    @Test fun repeatedRecordsIncrementCorrectBuckets() {
        var d = StatsData()
        d = StatsStore.applyRecord(d, "mafia", listOf("A"), "town", 1)
        d = StatsStore.applyRecord(d, "mafia", listOf("A"), "mafia", 2)
        d = StatsStore.applyRecord(d, "mafia", listOf("A"), "town", 3)
        val s = d.games["mafia"]!!
        assertEquals(3, s.playCount)
        assertEquals(2, s.outcomes["town"])
        assertEquals(1, s.outcomes["mafia"])
    }

    @Test fun distinctGamesTrackedIndependently() {
        var d = StatsData()
        d = StatsStore.applyRecord(d, "mafia", emptyList(), "town", 1)
        d = StatsStore.applyRecord(d, "codenames", emptyList(), "red", 2)
        assertEquals(1, d.games["mafia"]!!.playCount)
        assertEquals(1, d.games["codenames"]!!.playCount)
        assertEquals(1, d.games["codenames"]!!.outcomes["red"])
        assertEquals(null, d.games["mafia"]!!.outcomes["red"])
    }

    @Test fun recentIsNewestFirstAndCapped() {
        var d = StatsData()
        for (i in 1..60) d = StatsStore.applyRecord(d, "tag", emptyList(), "runners", i.toLong(), recentCap = 50)
        assertEquals(50, d.recent.size)
        // Newest (timestamp 60) first, oldest kept is 11.
        assertEquals(60L, d.recent.first().timestamp)
        assertEquals(11L, d.recent.last().timestamp)
        // playCount still counts every game even past the recent cap.
        assertEquals(60, d.games["tag"]!!.playCount)
    }

    @Test fun countOnlyOutcomeBucket() {
        var d = StatsData()
        d = StatsStore.applyRecord(d, "realtime", emptyList(), "played", 1)
        d = StatsStore.applyRecord(d, "realtime", emptyList(), "played", 2)
        val s = d.games["realtime"]!!
        assertEquals(2, s.playCount)
        assertEquals(2, s.outcomes["played"])
        assertTrue(s.outcomes.keys == setOf("played"))
    }
}
