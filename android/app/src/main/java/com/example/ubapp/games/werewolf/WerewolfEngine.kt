package com.example.ubapp.games.werewolf

import kotlin.random.Random

enum class WerewolfPhase { LOBBY, NIGHT, DAY_REVEAL, DAY_VOTE, HUNTER_SHOT, GAME_OVER }
enum class WerewolfWinner { WEREWOLVES, TOWN }

/** Host-configurable knobs. Defaults reproduce the formula-driven game. */
data class WerewolfOptions(
    val wolfCount: Int? = null,
    val seerEnabled: Boolean = true,
    val hunterEnabled: Boolean = true,
)

enum class WerewolfRole(val displayName: String, val tagline: String) {
    WEREWOLF("Werewolf", "Hunt the village. Coordinate with your pack at night."),
    SEER("Seer", "Each night, learn whether one player is a werewolf."),
    HUNTER("Hunter", "When you die, you take one player down with you."),
    VILLAGER("Villager", "No special ability. Survive and vote wisely.");

    val isTown: Boolean get() = this != WEREWOLF
    val hasNightAction: Boolean get() = this == WEREWOLF || this == SEER
}

class WerewolfPlayer(val id: String, val name: String, val isHost: Boolean) {
    var role: WerewolfRole? = null
    var alive: Boolean = true
}

data class WerewolfNightOutcome(val killedId: String?)
data class WerewolfDayOutcome(val eliminatedId: String?, val tally: Map<String, Int>)
data class SeerResult(val seerId: String, val targetId: String, val isWerewolf: Boolean)
data class HunterShot(val hunterId: String, val targetId: String)

class WerewolfEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, WerewolfPlayer> = linkedMapOf()
    var phase: WerewolfPhase = WerewolfPhase.LOBBY
    var day: Int = 0
    var winner: WerewolfWinner? = null
    var options: WerewolfOptions = WerewolfOptions()
        private set

    private val wolfVotes = mutableMapOf<String, String>()
    private var seerTarget: String? = null
    val dayVotes: MutableMap<String, String?> = mutableMapOf()

    var pendingHunterShooter: String? = null
    private var postHunterPhase: WerewolfPhase? = null

    var lastNight: WerewolfNightOutcome? = null
    var lastDay: WerewolfDayOutcome? = null
    var lastSeerResult: SeerResult? = null
    val hunterShotsThisRound = mutableListOf<HunterShot>()

    fun addPlayer(id: String, name: String, isHost: Boolean = false): WerewolfPlayer {
        val p = WerewolfPlayer(id, name, isHost); players[id] = p; return p
    }
    fun removePlayer(id: String) { if (phase == WerewolfPhase.LOBBY) players.remove(id) }
    val canStart: Boolean get() = phase == WerewolfPhase.LOBBY && players.size >= 5

    val maxWolfCount: Int get() = maxOf(1, players.size - 1)

    fun setOptions(o: WerewolfOptions) {
        if (phase != WerewolfPhase.LOBBY) return
        options = o.copy(wolfCount = o.wolfCount?.coerceIn(1, maxWolfCount))
    }

    fun start() {
        if (!canStart) return
        val ids = players.keys.toMutableList().also { it.shuffle(rng) }
        val formulaCount = (ids.size / 5).coerceIn(1, ids.size - 3)
        val wolfCount = (options.wolfCount ?: formulaCount).coerceIn(1, ids.size - 1)
        val includeHunter = options.hunterEnabled && ids.size >= 6
        var i = 0
        while (i < wolfCount) { players[ids[i]]!!.role = WerewolfRole.WEREWOLF; i++ }
        if (options.seerEnabled && i < ids.size) { players[ids[i]]!!.role = WerewolfRole.SEER; i++ }
        if (includeHunter && i < ids.size) { players[ids[i]]!!.role = WerewolfRole.HUNTER; i++ }
        while (i < ids.size) { players[ids[i]]!!.role = WerewolfRole.VILLAGER; i++ }
        phase = WerewolfPhase.NIGHT
        day = 1
    }

    val aliveWolves get() = players.values.filter { it.alive && it.role == WerewolfRole.WEREWOLF }
    val aliveSeers get() = players.values.filter { it.alive && it.role == WerewolfRole.SEER }
    val alive get() = players.values.filter { it.alive }
    val dead get() = players.values.filter { !it.alive }

    fun submitWolfVote(voterId: String, targetId: String): Boolean {
        if (phase != WerewolfPhase.NIGHT) return false
        val voter = players[voterId] ?: return false
        if (!voter.alive || voter.role != WerewolfRole.WEREWOLF) return false
        val target = players[targetId] ?: return false
        if (!target.alive || target.role == WerewolfRole.WEREWOLF) return false
        wolfVotes[voterId] = targetId
        return isNightReady()
    }

    fun submitSeerTarget(seerId: String, targetId: String): Boolean {
        if (phase != WerewolfPhase.NIGHT) return false
        val seer = players[seerId] ?: return false
        if (!seer.alive || seer.role != WerewolfRole.SEER) return false
        val target = players[targetId] ?: return false
        if (!target.alive || targetId == seerId) return false
        seerTarget = targetId
        return isNightReady()
    }

    private fun isNightReady(): Boolean {
        val wolves = aliveWolves.all { wolfVotes.containsKey(it.id) }
        val seer = aliveSeers.isEmpty() || seerTarget != null
        return wolves && seer
    }

    fun resolveNight(): WerewolfNightOutcome {
        val tally = mutableMapOf<String, Int>()
        for (t in wolfVotes.values) tally[t] = (tally[t] ?: 0) + 1
        val killTarget = uniqueMax(tally)
        val st = seerTarget
        if (st != null) {
            val seer = aliveSeers.firstOrNull(); val target = players[st]
            if (seer != null && target != null) {
                lastSeerResult = SeerResult(seer.id, target.id, target.role == WerewolfRole.WEREWOLF)
            }
        } else lastSeerResult = null
        hunterShotsThisRound.clear()
        killTarget?.let { killPlayer(it) }
        val out = WerewolfNightOutcome(killedId = killTarget)
        lastNight = out
        wolfVotes.clear(); seerTarget = null
        if (checkWin()) return out
        if (pendingHunterShooter != null) {
            postHunterPhase = WerewolfPhase.DAY_REVEAL; phase = WerewolfPhase.HUNTER_SHOT
        } else phase = WerewolfPhase.DAY_REVEAL
        return out
    }

    fun advanceToDayVote() {
        if (phase != WerewolfPhase.DAY_REVEAL) return
        dayVotes.clear()
        if (checkWin()) return
        phase = WerewolfPhase.DAY_VOTE
    }

    fun submitDayVote(voterId: String, targetId: String?): Boolean {
        if (phase != WerewolfPhase.DAY_VOTE) return false
        val voter = players[voterId] ?: return false
        if (!voter.alive) return false
        if (targetId != null) {
            val t = players[targetId] ?: return false; if (!t.alive) return false
        }
        dayVotes[voterId] = targetId
        return alive.all { dayVotes.containsKey(it.id) }
    }

    fun resolveDay(): WerewolfDayOutcome {
        val tally = mutableMapOf<String, Int>()
        for (t in dayVotes.values) if (t != null) tally[t] = (tally[t] ?: 0) + 1
        val candidate = uniqueMax(tally)
        var eliminated: String? = null
        if (candidate != null) { val max = tally[candidate]!!; if (max * 2 > alive.size) eliminated = candidate }
        hunterShotsThisRound.clear()
        eliminated?.let { killPlayer(it) }
        val out = WerewolfDayOutcome(eliminatedId = eliminated, tally = tally)
        lastDay = out
        if (checkWin()) return out
        if (pendingHunterShooter != null) {
            postHunterPhase = WerewolfPhase.NIGHT; phase = WerewolfPhase.HUNTER_SHOT
        } else { day += 1; phase = WerewolfPhase.NIGHT }
        return out
    }

    fun submitHunterShot(hunterId: String, targetId: String): Boolean {
        if (phase != WerewolfPhase.HUNTER_SHOT || pendingHunterShooter != hunterId) return false
        val target = players[targetId] ?: return false
        if (!target.alive || targetId == hunterId) return false
        pendingHunterShooter = null
        hunterShotsThisRound.add(HunterShot(hunterId, targetId))
        killPlayer(targetId)
        if (checkWin()) return true
        if (pendingHunterShooter != null) return true
        val returnTo = postHunterPhase ?: WerewolfPhase.DAY_REVEAL
        postHunterPhase = null
        if (returnTo == WerewolfPhase.NIGHT) day += 1
        phase = returnTo
        return true
    }

    private fun killPlayer(id: String) {
        val p = players[id] ?: return
        if (!p.alive) return
        p.alive = false
        if (p.role == WerewolfRole.HUNTER) pendingHunterShooter = id
    }

    private fun checkWin(): Boolean {
        val liveWolves = aliveWolves.size
        val liveTown = alive.count { it.role != WerewolfRole.WEREWOLF }
        if (liveWolves == 0) { winner = WerewolfWinner.TOWN; phase = WerewolfPhase.GAME_OVER; return true }
        if (liveWolves >= liveTown) { winner = WerewolfWinner.WEREWOLVES; phase = WerewolfPhase.GAME_OVER; return true }
        return false
    }

    private fun uniqueMax(tally: Map<String, Int>): String? {
        var max = 0; val tied = mutableListOf<String>()
        for ((id, c) in tally) {
            if (c > max) { max = c; tied.clear(); tied.add(id) }
            else if (c == max) tied.add(id)
        }
        return if (tied.size == 1) tied[0] else null
    }
}
