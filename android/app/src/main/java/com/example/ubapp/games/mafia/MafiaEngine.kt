package com.example.ubapp.games.mafia

import kotlin.random.Random

enum class MafiaPhase { LOBBY, NIGHT, DAY_REVEAL, DAY_VOTE, GAME_OVER }
enum class MafiaWinner { MAFIA, TOWN }

enum class MafiaRole(val displayName: String, val tagline: String) {
    MAFIA("Mafia", "Eliminate the town. Coordinate with your fellow mafia at night."),
    DOCTOR("Doctor", "Save one player each night. You can self-save once per game."),
    VILLAGER("Villager", "You have no special ability. Use your vote during the day.");

    val isTown: Boolean get() = this != MAFIA
    val hasNightAction: Boolean get() = this == MAFIA || this == DOCTOR
}

class MafiaPlayer(val id: String, val name: String, val isHost: Boolean) {
    var role: MafiaRole? = null
    var alive: Boolean = true
}

data class MafiaNightOutcome(val killedId: String?, val savedId: String?)
data class MafiaDayOutcome(val eliminatedId: String?, val tally: Map<String, Int>)

/**
 * Pure game logic. The server adapter is responsible for collecting messages
 * and feeding them in; the engine never touches network code.
 */
class MafiaEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, MafiaPlayer> = linkedMapOf()
    var phase: MafiaPhase = MafiaPhase.LOBBY
    var day: Int = 0
    var winner: MafiaWinner? = null

    private val mafiaVotes = mutableMapOf<String, String>()
    private var doctorTarget: String? = null
    private var doctorSelfSaveUsed = false

    val dayVotes: MutableMap<String, String?> = mutableMapOf()
    var lastNight: MafiaNightOutcome? = null
    var lastDay: MafiaDayOutcome? = null

    fun addPlayer(id: String, name: String, isHost: Boolean = false): MafiaPlayer {
        val p = MafiaPlayer(id, name, isHost)
        players[id] = p
        return p
    }
    fun removePlayer(id: String) { if (phase == MafiaPhase.LOBBY) players.remove(id) }

    val canStart: Boolean get() = phase == MafiaPhase.LOBBY && players.size >= 4

    fun start() {
        if (!canStart) return
        val ids = players.keys.toMutableList().also { it.shuffle(rng) }
        val mafiaCount = (ids.size / 4).coerceIn(1, ids.size - 2)
        for (i in ids.indices) {
            val p = players[ids[i]]!!
            p.role = when {
                i < mafiaCount -> MafiaRole.MAFIA
                i == mafiaCount -> MafiaRole.DOCTOR
                else -> MafiaRole.VILLAGER
            }
        }
        phase = MafiaPhase.NIGHT
        day = 1
    }

    val aliveMafia get() = players.values.filter { it.alive && it.role == MafiaRole.MAFIA }
    val aliveDoctors get() = players.values.filter { it.alive && it.role == MafiaRole.DOCTOR }
    val alive get() = players.values.filter { it.alive }
    val dead get() = players.values.filter { !it.alive }

    fun submitMafiaVote(voterId: String, targetId: String): Boolean {
        if (phase != MafiaPhase.NIGHT) return false
        val voter = players[voterId] ?: return false
        if (!voter.alive || voter.role != MafiaRole.MAFIA) return false
        val target = players[targetId] ?: return false
        if (!target.alive) return false
        mafiaVotes[voterId] = targetId
        return isNightReady()
    }

    fun submitDoctorTarget(doctorId: String, targetId: String): Boolean {
        if (phase != MafiaPhase.NIGHT) return false
        val doc = players[doctorId] ?: return false
        if (!doc.alive || doc.role != MafiaRole.DOCTOR) return false
        val target = players[targetId] ?: return false
        if (!target.alive) return false
        if (targetId == doctorId && doctorSelfSaveUsed) return false
        doctorTarget = targetId
        return isNightReady()
    }

    private fun isNightReady(): Boolean {
        val mafiaSubmitted = aliveMafia.all { mafiaVotes.containsKey(it.id) }
        val doctorSubmitted = aliveDoctors.isEmpty() || doctorTarget != null
        return mafiaSubmitted && doctorSubmitted
    }

    fun resolveNight(): MafiaNightOutcome {
        val tally = mutableMapOf<String, Int>()
        for (t in mafiaVotes.values) tally[t] = (tally[t] ?: 0) + 1
        var killTarget = uniqueMax(tally)
        var saved: String? = null
        val dt = doctorTarget
        if (dt != null && dt == killTarget) {
            saved = dt
            if (dt == aliveDoctors.firstOrNull()?.id) doctorSelfSaveUsed = true
            killTarget = null
        }
        killTarget?.let { players[it]?.alive = false }
        val out = MafiaNightOutcome(killedId = killTarget, savedId = saved)
        lastNight = out
        mafiaVotes.clear(); doctorTarget = null
        phase = MafiaPhase.DAY_REVEAL
        return out
    }

    fun advanceToDayVote() {
        if (phase != MafiaPhase.DAY_REVEAL) return
        dayVotes.clear()
        if (checkWin()) return
        phase = MafiaPhase.DAY_VOTE
    }

    fun submitDayVote(voterId: String, targetId: String?): Boolean {
        if (phase != MafiaPhase.DAY_VOTE) return false
        val voter = players[voterId] ?: return false
        if (!voter.alive) return false
        if (targetId != null) {
            val t = players[targetId] ?: return false
            if (!t.alive) return false
        }
        dayVotes[voterId] = targetId
        return alive.all { dayVotes.containsKey(it.id) }
    }

    fun resolveDay(): MafiaDayOutcome {
        val tally = mutableMapOf<String, Int>()
        for (t in dayVotes.values) if (t != null) tally[t] = (tally[t] ?: 0) + 1
        val candidate = uniqueMax(tally)
        var eliminated: String? = null
        if (candidate != null) {
            val max = tally[candidate]!!
            if (max * 2 > alive.size) eliminated = candidate
        }
        eliminated?.let { players[it]?.alive = false }
        val out = MafiaDayOutcome(eliminatedId = eliminated, tally = tally)
        lastDay = out
        if (checkWin()) return out
        day += 1
        phase = MafiaPhase.NIGHT
        return out
    }

    private fun checkWin(): Boolean {
        val liveMafiaCount = aliveMafia.size
        val liveTownCount = alive.count { it.role != MafiaRole.MAFIA }
        if (liveMafiaCount == 0) { winner = MafiaWinner.TOWN; phase = MafiaPhase.GAME_OVER; return true }
        if (liveMafiaCount >= liveTownCount) { winner = MafiaWinner.MAFIA; phase = MafiaPhase.GAME_OVER; return true }
        return false
    }

    private fun uniqueMax(tally: Map<String, Int>): String? {
        var max = 0
        val tied = mutableListOf<String>()
        for ((id, c) in tally) {
            if (c > max) { max = c; tied.clear(); tied.add(id) }
            else if (c == max) tied.add(id)
        }
        return if (tied.size == 1) tied[0] else null
    }
}
