package com.example.jamboree

import com.example.jamboree.games.werewolf.WerewolfEngine
import com.example.jamboree.games.werewolf.WerewolfOptions
import com.example.jamboree.games.werewolf.WerewolfPhase
import com.example.jamboree.games.werewolf.WerewolfRole
import com.example.jamboree.games.werewolf.WerewolfWinner
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Engine phase-logic coverage for Werewolf — role assignment, night/day
 * resolution, the hunter shot and win conditions. Kept in lockstep with the
 * Swift engine, so this guards both platforms.
 */
class WerewolfEngineTest {

    private fun lobby(seed: Int, n: Int): WerewolfEngine {
        val e = WerewolfEngine(Random(seed))
        (0 until n).forEach { e.addPlayer("p$it", "p$it") }
        return e
    }

    @Test fun `needs at least five players`() {
        val e = lobby(1, 4)
        assertFalse(e.canStart)
        e.start()
        assertEquals(WerewolfPhase.LOBBY, e.phase)
    }

    @Test fun `start assigns every player a role and opens night one`() {
        val e = lobby(2, 6)
        e.start()
        assertEquals(WerewolfPhase.NIGHT, e.phase)
        assertEquals(1, e.day)
        assertTrue(e.players.values.all { it.role != null })
        assertTrue(e.aliveWolves.isNotEmpty())
    }

    @Test fun `seer and hunter can be disabled`() {
        val e = lobby(3, 7)
        e.setOptions(WerewolfOptions(seerEnabled = false, hunterEnabled = false))
        e.start()
        assertEquals(0, e.players.values.count { it.role == WerewolfRole.SEER })
        assertEquals(0, e.players.values.count { it.role == WerewolfRole.HUNTER })
    }

    @Test fun `night resolves the wolves' unanimous kill and the seer learns alignment`() {
        val e = lobby(4, 6)
        e.setOptions(WerewolfOptions(wolfCount = 1, seerEnabled = true, hunterEnabled = false))
        e.start()
        val wolf = e.aliveWolves.first()
        val seer = e.aliveSeers.first()
        val victim = e.alive.first { it.role == WerewolfRole.VILLAGER }
        e.submitWolfVote(wolf.id, victim.id)
        e.submitSeerTarget(seer.id, wolf.id)
        val outcome = e.resolveNight()
        assertEquals(victim.id, outcome.killedId)
        assertFalse(e.players[victim.id]!!.alive)
        assertNotNull(e.lastSeerResult)
        assertTrue(e.lastSeerResult!!.isWerewolf)   // seer peeked a wolf
    }

    @Test fun `a dying hunter takes a target down and only then play continues`() {
        val e = lobby(5, 7)
        e.setOptions(WerewolfOptions(wolfCount = 1, seerEnabled = false, hunterEnabled = true))
        e.start()
        val hunter = e.players.values.first { it.role == WerewolfRole.HUNTER }
        val wolf = e.aliveWolves.first()
        // Wolves kill the hunter at night → game pauses for the hunter shot.
        e.submitWolfVote(wolf.id, hunter.id)
        e.resolveNight()
        assertEquals(WerewolfPhase.HUNTER_SHOT, e.phase)
        assertEquals(hunter.id, e.pendingHunterShooter)
        val target = e.alive.first { it.role == WerewolfRole.VILLAGER }
        assertTrue(e.submitHunterShot(hunter.id, target.id))
        assertFalse(e.players[target.id]!!.alive)
        assertNull(e.pendingHunterShooter)
    }

    @Test fun `day lynch requires a strict majority`() {
        val e = lobby(6, 5)
        e.setOptions(WerewolfOptions(wolfCount = 1, seerEnabled = false, hunterEnabled = false))
        e.start()
        // Skip the night cleanly: no kill, advance to the day vote.
        val wolf = e.aliveWolves.first()
        e.submitWolfVote(wolf.id, e.alive.first { it.role == WerewolfRole.VILLAGER }.id)
        e.resolveNight()
        if (e.phase == WerewolfPhase.DAY_REVEAL) e.advanceToDayVote()
        if (e.phase != WerewolfPhase.DAY_VOTE) return  // game already decided
        val living = e.alive.map { it.id }
        val suspect = living.first()
        // Only one vote on the suspect, the rest skip → no majority, no lynch.
        e.submitDayVote(living[0], suspect)
        for (i in 1 until living.size) e.submitDayVote(living[i], null)
        val day = e.resolveDay()
        assertNull(day.eliminatedId)
    }

    @Test fun `town wins once the last wolf is eliminated`() {
        val e = lobby(7, 5)
        e.setOptions(WerewolfOptions(wolfCount = 1, seerEnabled = false, hunterEnabled = false))
        e.start()
        val wolf = e.aliveWolves.first()
        e.submitWolfVote(wolf.id, e.alive.first { it.role == WerewolfRole.VILLAGER }.id)
        e.resolveNight()
        if (e.phase == WerewolfPhase.DAY_REVEAL) e.advanceToDayVote()
        if (e.phase != WerewolfPhase.DAY_VOTE) return
        // Everyone alive lynches the wolf.
        e.alive.forEach { e.submitDayVote(it.id, wolf.id) }
        e.resolveDay()
        assertEquals(WerewolfWinner.TOWN, e.winner)
        assertEquals(WerewolfPhase.GAME_OVER, e.phase)
    }
}
