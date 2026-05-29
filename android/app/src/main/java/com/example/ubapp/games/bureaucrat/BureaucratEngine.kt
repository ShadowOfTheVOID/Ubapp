package com.example.ubapp.games.bureaucrat

import kotlin.random.Random

enum class BureaucratPhase { LOBBY, ARGUING, REBUTTAL, ROUND_OVER, GAME_OVER }

/** Why a round ended — drives the round-over copy on every client. */
enum class RoundEndReason { LOOPHOLE_TIMEOUT, LOOPHOLE_CONTRADICTION, BUREAUCRAT_SURVIVED, TOKENS_EXHAUSTED }

/** Host-configurable knobs. Defaults reproduce the reference rules. */
data class BureaucratOptions(
    /** First player to this score wins the game. */
    val targetScore: Int = 10,
    /** Loophole challenges each citizen may spend per round. */
    val challengeTokens: Int = 2,
    /** Seconds the bureaucrat has to type a rebuttal. Stored so every client
     *  can render the same countdown; the *server* owns the actual timer. */
    val rebuttalSeconds: Int = 20,
    /** When true the server consults a [ContradictionDetector] on each rebuttal;
     *  purely a UI/broadcast hint here — the engine stays transport-agnostic. */
    val aiAssist: Boolean = true,
)

class BureaucratPlayer(val id: String, val name: String, val isHost: Boolean) {
    var score: Int = 0
}

/** One line in the binding policy log. */
data class PolicyEntry(
    val text: String,
    /** false for the bureaucrat's own denials, true for forced rebuttals to a loophole. */
    val isRebuttal: Boolean,
    /** Citizen whose loophole prompted this rebuttal (rebuttals only). */
    val challengerId: String? = null,
)

data class RoundOutcome(
    val bureaucratId: String,
    val challengerId: String?,
    val reason: RoundEndReason,
    val task: String,
)

/**
 * Pure game logic for "The Bureaucrat".
 *
 * One player is the Bureaucrat; everyone else is a Citizen with a shared
 * absurd task. The Bureaucrat denies requests, each denial appended to a
 * binding policy log. A citizen may spend a token to "call a loophole",
 * which forces the Bureaucrat to type a rebuttal before a server-owned
 * timer elapses. If the rebuttal never comes ([rebuttalTimedOut]) or it
 * contradicts the existing log (the boolean the server feeds into
 * [submitRebuttal]), the citizen wins the round.
 *
 * The engine never touches I/O: the countdown and the contradiction check
 * both live in the server adapter, which drives the engine with explicit
 * events. This keeps it a deterministic state machine, identical to the
 * Swift engine and exercised by [BureaucratEngineTest].
 */
class BureaucratEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, BureaucratPlayer> = linkedMapOf()
    var phase: BureaucratPhase = BureaucratPhase.LOBBY
    var roundNumber: Int = 0
    var bureaucratId: String? = null
    var task: String? = null
    var winnerId: String? = null
    var options: BureaucratOptions = BureaucratOptions()
        private set

    val policyLog: MutableList<PolicyEntry> = mutableListOf()
    var pendingChallenger: String? = null
        private set
    val tokens: MutableMap<String, Int> = mutableMapOf()
    var lastRound: RoundOutcome? = null
        private set

    /** Rotation cursor over [order]; the bureaucrat is order[rotation % size]. */
    private var rotation: Int = 0

    private companion object {
        const val SURVIVE_REWARD = 2
        const val LOOPHOLE_REWARD = 3
        const val FAIL_PENALTY = 1
    }

    private val order: List<String> get() = players.keys.toList()

    fun addPlayer(id: String, name: String, isHost: Boolean = false): BureaucratPlayer {
        val p = BureaucratPlayer(id, name, isHost)
        players[id] = p
        return p
    }

    fun removePlayer(id: String) { if (phase == BureaucratPhase.LOBBY) players.remove(id) }

    val canStart: Boolean get() = phase == BureaucratPhase.LOBBY && players.size >= 3

    fun setOptions(o: BureaucratOptions) {
        if (phase != BureaucratPhase.LOBBY) return
        options = o.copy(
            targetScore = o.targetScore.coerceIn(3, 50),
            challengeTokens = o.challengeTokens.coerceIn(1, 9),
            rebuttalSeconds = o.rebuttalSeconds.coerceIn(5, 120),
        )
    }

    val citizens: List<BureaucratPlayer>
        get() = players.values.filter { it.id != bureaucratId }

    fun tokensFor(id: String): Int = tokens[id] ?: 0

    fun start() {
        if (!canStart) return
        rotation = 0
        for (p in players.values) p.score = 0
        beginRound()
    }

    private fun beginRound() {
        val ids = order
        if (ids.isEmpty()) return
        bureaucratId = ids[rotation % ids.size]
        task = TASKS[rng.nextInt(TASKS.size)]
        policyLog.clear()
        pendingChallenger = null
        tokens.clear()
        for (c in citizens) tokens[c.id] = options.challengeTokens
        roundNumber += 1
        phase = BureaucratPhase.ARGUING
    }

    /** Bureaucrat appends a binding denial. Returns false if rejected. */
    fun addDenial(playerId: String, text: String): Boolean {
        if (phase != BureaucratPhase.ARGUING) return false
        if (playerId != bureaucratId) return false
        val t = text.trim()
        if (t.isEmpty()) return false
        policyLog.add(PolicyEntry(t, isRebuttal = false))
        return true
    }

    /** A citizen spends a token to challenge. Returns false if not allowed. */
    fun callLoophole(citizenId: String): Boolean {
        if (phase != BureaucratPhase.ARGUING) return false
        if (citizenId == bureaucratId) return false
        if (players[citizenId] == null) return false
        if (tokensFor(citizenId) <= 0) return false
        pendingChallenger = citizenId
        phase = BureaucratPhase.REBUTTAL
        return true
    }

    /**
     * Bureaucrat answers the open loophole. [contradicts] is the verdict the
     * server's [ContradictionDetector] returned for this rebuttal against the
     * prior log — true means the rebuttal (or the log it leans on) is
     * self-contradictory, so the loophole stands and the challenger wins.
     */
    fun submitRebuttal(text: String, contradicts: Boolean): Boolean {
        if (phase != BureaucratPhase.REBUTTAL) return false
        val challenger = pendingChallenger ?: return false
        val t = text.trim()
        if (t.isEmpty()) return false
        if (contradicts) {
            policyLog.add(PolicyEntry(t, isRebuttal = true, challengerId = challenger))
            awardLoophole(challenger, RoundEndReason.LOOPHOLE_CONTRADICTION)
            return true
        }
        // Successful defence: the rebuttal becomes binding policy and the
        // challenger burns the token they spent.
        policyLog.add(PolicyEntry(t, isRebuttal = true, challengerId = challenger))
        tokens[challenger] = (tokensFor(challenger) - 1).coerceAtLeast(0)
        players[challenger]?.let { it.score = (it.score - FAIL_PENALTY).coerceAtLeast(0) }
        pendingChallenger = null
        phase = BureaucratPhase.ARGUING
        if (citizens.all { tokensFor(it.id) <= 0 }) {
            bureaucratSurvives(RoundEndReason.TOKENS_EXHAUSTED)
        }
        return true
    }

    /** Server-owned timer elapsed with no rebuttal: the challenger wins. */
    fun rebuttalTimedOut(): Boolean {
        if (phase != BureaucratPhase.REBUTTAL) return false
        val challenger = pendingChallenger ?: return false
        awardLoophole(challenger, RoundEndReason.LOOPHOLE_TIMEOUT)
        return true
    }

    /** Host calls the round for the Bureaucrat (debate fizzled / time up). */
    fun bureaucratSurvives(reason: RoundEndReason = RoundEndReason.BUREAUCRAT_SURVIVED): Boolean {
        if (phase != BureaucratPhase.ARGUING && phase != BureaucratPhase.REBUTTAL) return false
        val b = bureaucratId ?: return false
        players[b]?.let { it.score += SURVIVE_REWARD }
        endRound(challenger = null, reason = reason)
        return true
    }

    private fun awardLoophole(challenger: String, reason: RoundEndReason) {
        players[challenger]?.let { it.score += LOOPHOLE_REWARD }
        endRound(challenger = challenger, reason = reason)
    }

    private fun endRound(challenger: String?, reason: RoundEndReason) {
        lastRound = RoundOutcome(bureaucratId!!, challenger, reason, task ?: "")
        pendingChallenger = null
        phase = BureaucratPhase.ROUND_OVER
    }

    /** Advance from the round-over screen: next round, or game over on target. */
    fun nextRound(): Boolean {
        if (phase != BureaucratPhase.ROUND_OVER) return false
        val leader = players.values.maxByOrNull { it.score }
        if (leader != null && leader.score >= options.targetScore) {
            winnerId = leader.id
            phase = BureaucratPhase.GAME_OVER
            return true
        }
        rotation += 1
        beginRound()
        return true
    }

    /** Bureaucrat for the upcoming round (used by the round-over preview). */
    fun nextBureaucratId(): String? {
        val ids = order
        if (ids.isEmpty()) return null
        return ids[(rotation + 1) % ids.size]
    }
}

/** Absurd shared tasks. Kept identical to the Swift `BureaucratTasks`. */
internal val TASKS: List<String> = listOf(
    "Register my deceased goldfish as a co-signer on my mortgage.",
    "Renew my expired dragon-riding permit.",
    "Appeal the noise complaint filed against my thoughts.",
    "Claim a tax deduction for emotional damage caused by Mondays.",
    "Get a parking permit for a vehicle that exists only in my dreams.",
    "Officially change my legal name to a sound I can only hum.",
    "File for joint custody of an idea I shared with a coworker.",
    "Obtain a refund for a sunset that did not meet expectations.",
    "Register my houseplant as an emotional support colleague.",
    "Request planning permission to build a moat around my desk.",
    "Apply for a passport for my reflection.",
    "Report my shadow as a lost item.",
    "Get a permit to whistle indoors on a Tuesday.",
    "Have last Thursday officially declared null and void.",
    "License my sourdough starter as a registered dependent.",
    "Appeal gravity on the grounds of personal inconvenience.",
)
