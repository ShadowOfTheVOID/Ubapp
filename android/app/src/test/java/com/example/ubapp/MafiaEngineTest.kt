package com.example.ubapp

import com.example.ubapp.games.mafia.MafiaEngine
import com.example.ubapp.games.mafia.MafiaPhase
import com.example.ubapp.games.mafia.MafiaRole
import com.example.ubapp.games.mafia.MafiaWinner
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MafiaEngineTest {
    @Test fun `cannot start with fewer than four players`() {
        val e = MafiaEngine()
        listOf("a", "b", "c").forEach { e.addPlayer(it, it) }
        assertFalse(e.canStart)
        e.start()
        assertEquals(MafiaPhase.LOBBY, e.phase)
    }

    @Test fun `start with four players assigns one mafia one doctor two villagers`() {
        val e = MafiaEngine(Random(42))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.start()
        assertEquals(MafiaPhase.NIGHT, e.phase)
        assertEquals(1, e.day)
        val roles = e.players.values.groupingBy { it.role!! }.eachCount()
        assertEquals(1, roles[MafiaRole.MAFIA])
        assertEquals(1, roles[MafiaRole.DOCTOR])
        assertEquals(2, roles[MafiaRole.VILLAGER])
    }

    @Test fun `night resolves once mafia and doctor have submitted`() {
        val e = setupRound(rng = Random(7))
        val mafia = e.players.values.first { it.role == MafiaRole.MAFIA }
        val doctor = e.players.values.first { it.role == MafiaRole.DOCTOR }
        val villagers = e.players.values.filter { it.role == MafiaRole.VILLAGER }
        // Mafia targets a villager, doctor saves a different player.
        assertFalse(e.submitMafiaVote(mafia.id, villagers[0].id), "mafia alone shouldn't be ready")
        assertTrue(e.submitDoctorTarget(doctor.id, villagers[1].id))
        val out = e.resolveNight()
        assertEquals(villagers[0].id, out.killedId)
        assertNull(out.savedId)
        assertFalse(e.players[villagers[0].id]!!.alive)
        assertEquals(MafiaPhase.DAY_REVEAL, e.phase)
    }

    @Test fun `doctor save cancels mafia kill`() {
        val e = setupRound(rng = Random(11))
        val mafia = e.players.values.first { it.role == MafiaRole.MAFIA }
        val doctor = e.players.values.first { it.role == MafiaRole.DOCTOR }
        val target = e.players.values.first { it.role == MafiaRole.VILLAGER }
        e.submitMafiaVote(mafia.id, target.id)
        e.submitDoctorTarget(doctor.id, target.id)
        val out = e.resolveNight()
        assertNull(out.killedId)
        assertEquals(target.id, out.savedId)
        assertTrue(e.players[target.id]!!.alive)
    }

    @Test fun `town wins when last mafia is lynched`() {
        // Force a deterministic role split.
        val e = MafiaEngine(Random(0))
        listOf("a", "b", "c", "d", "e").forEach { e.addPlayer(it, it) }
        e.start()
        // Make 'a' the only mafia, ignore the random outcome by overriding.
        for (p in e.players.values) p.role = MafiaRole.VILLAGER
        e.players["a"]!!.role = MafiaRole.MAFIA
        e.players["b"]!!.role = MafiaRole.DOCTOR

        // Skip a night: mafia votes for 'c', doctor saves 'd'.
        e.submitMafiaVote("a", "c"); e.submitDoctorTarget("b", "d")
        e.resolveNight()
        e.advanceToDayVote()
        // Everyone votes for 'a' (the mafia).
        for (p in e.alive) e.submitDayVote(p.id, "a")
        e.resolveDay()
        assertEquals(MafiaPhase.GAME_OVER, e.phase)
        assertEquals(MafiaWinner.TOWN, e.winner)
    }

    @Test fun `mafia wins when they equal town`() {
        val e = MafiaEngine(Random(1))
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.start()
        for (p in e.players.values) p.role = MafiaRole.VILLAGER
        e.players["a"]!!.role = MafiaRole.MAFIA
        e.players["b"]!!.role = MafiaRole.DOCTOR
        // Mafia kills the doctor's saved miss.
        e.submitMafiaVote("a", "c"); e.submitDoctorTarget("b", "b")
        e.resolveNight()  // 'c' dies
        e.advanceToDayVote()
        // Vote ties → no elimination; 2 alive non-mafia, 1 mafia → not yet win.
        // Force a second night: mafia kills 'd'.
        for (id in listOf("a", "b", "d")) e.submitDayVote(id, null)
        e.resolveDay() // no majority → no elim
        assertEquals(MafiaPhase.NIGHT, e.phase)
        e.submitMafiaVote("a", "d"); e.submitDoctorTarget("b", "b")
        e.resolveNight()
        e.advanceToDayVote()
        // After 'd' dies: alive = {a (mafia), b (doctor)} → mafia >= town
        assertEquals(MafiaPhase.GAME_OVER, e.phase)
        assertEquals(MafiaWinner.MAFIA, e.winner)
    }

    private fun setupRound(rng: Random): MafiaEngine {
        val e = MafiaEngine(rng)
        listOf("a", "b", "c", "d").forEach { e.addPlayer(it, it) }
        e.start()
        assertNotNull(e.players["a"]!!.role)
        return e
    }
}
