package com.example.jamboree

import com.example.jamboree.games.tag.ProximityDetector
import com.example.jamboree.games.tag.ProximityEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Regression net for the pure [ProximityDetector] sliding-window + hysteresis
 * logic. The Swift detector is kept identical, so this guards both platforms.
 *
 * The headline case is the bug report "I bring the phones together and it
 * doesn't tag": phone-to-phone shielding makes a held-close pair read around
 * -65…-75 dBm, so the enter gate must fire there rather than only at the
 * -40…-55 a clear-air link would give.
 */
class ProximityDetectorTest {

    private fun ev(rssi: Int, peer: String = "p1") = ProximityEvent(peer, rssi, 0L)

    @Test fun `phones held together at typical shielded rssi fires a touch`() {
        val touched = mutableListOf<String>()
        val det = ProximityDetector(onTouch = { touched.add(it) })
        // -70 dBm is a realistic reading for two phones pressed together.
        repeat(4) { det.ingest(ev(-70)) }
        assertEquals(listOf("p1"), touched)
    }

    @Test fun `a peer across the room does not fire`() {
        val touched = mutableListOf<String>()
        val det = ProximityDetector(onTouch = { touched.add(it) })
        repeat(6) { det.ingest(ev(-90)) }
        assertTrue(touched.isEmpty())
    }

    @Test fun `does not re-fire while staying close`() {
        var count = 0
        val det = ProximityDetector(onTouch = { count++ })
        repeat(10) { det.ingest(ev(-68)) }
        assertEquals(1, count)
    }

    @Test fun `hysteresis requires leaving before a second touch`() {
        var count = 0
        val det = ProximityDetector(onTouch = { count++ })
        // Come close → fire once.
        repeat(4) { det.ingest(ev(-68)) }
        assertEquals(1, count)
        // Drift to a value between exit and enter: still "inside", no re-fire.
        repeat(4) { det.ingest(ev(-78)) }
        assertEquals(1, count)
        // Move well away (past exitDbm) → now "outside".
        repeat(4) { det.ingest(ev(-95)) }
        // Come back close → fires again.
        repeat(4) { det.ingest(ev(-68)) }
        assertEquals(2, count)
    }

    @Test fun `immunity suppresses the next touch within the window`() {
        var count = 0
        val det = ProximityDetector(onTouch = { count++ })
        det.grantImmunity("p1")
        // Even arriving close, an immune peer is skipped on its enter transition.
        repeat(4) { det.ingest(ev(-68)) }
        assertEquals(0, count)
    }

    @Test fun `the averaging window smooths a single far outlier`() {
        val touched = mutableListOf<String>()
        val det = ProximityDetector(onTouch = { touched.add(it) })
        // Three close readings then one far blip: average stays inside the gate.
        det.ingest(ev(-68))
        det.ingest(ev(-68))
        det.ingest(ev(-68))
        det.ingest(ev(-92))
        assertEquals(listOf("p1"), touched)
    }
}
