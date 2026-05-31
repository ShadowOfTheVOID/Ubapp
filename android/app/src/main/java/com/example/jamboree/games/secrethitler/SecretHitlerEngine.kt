package com.example.ubapp.games.secrethitler

import kotlin.random.Random

enum class SecretHitlerPhase(val wire: String) {
    LOBBY("lobby"),
    NOMINATION("nomination"),
    ELECTION("election"),
    PRESIDENT_DISCARD("presidentDiscard"),
    CHANCELLOR_ENACT("chancellorEnact"),
    VETO_DECISION("vetoDecision"),
    POLICY_PEEK("policyPeek"),
    INVESTIGATION("investigation"),
    INVESTIGATION_REVEAL("investigationReveal"),
    SPECIAL_ELECTION("specialElection"),
    EXECUTION("execution"),
    GAME_OVER("gameOver"),
}

enum class SecretHitlerRole(val wire: String) {
    LIBERAL("liberal"), FASCIST("fascist"), HITLER("hitler");

    val party: SecretHitlerParty
        get() = if (this == LIBERAL) SecretHitlerParty.LIBERAL else SecretHitlerParty.FASCIST
}

enum class SecretHitlerParty(val wire: String) { LIBERAL("liberal"), FASCIST("fascist") }
enum class SecretHitlerPolicy(val wire: String) { LIBERAL("liberal"), FASCIST("fascist") }
enum class SecretHitlerWinner(val wire: String) { LIBERAL("liberal"), FASCIST("fascist") }
enum class SecretHitlerWinReason(val wire: String) {
    FIVE_LIBERAL_POLICIES("fiveLiberalPolicies"),
    SIX_FASCIST_POLICIES("sixFascistPolicies"),
    HITLER_ELECTED_CHANCELLOR("hitlerElectedChancellor"),
    HITLER_EXECUTED("hitlerExecuted"),
}

class SecretHitlerPlayer(val id: String, val name: String, val isHost: Boolean) {
    var role: SecretHitlerRole? = null
    var alive: Boolean = true
}

data class SecretHitlerInvestigation(val subjectId: String, val party: SecretHitlerParty)

/**
 * Pure game logic for Secret Hitler. Mirrors SecretHitlerEngine.swift —
 * supports 5–10 players. The server adapter feeds in events; the engine
 * never touches network or UI code.
 */
class SecretHitlerEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()

    val players: MutableMap<String, SecretHitlerPlayer> = linkedMapOf()
    val seatOrder: MutableList<String> = mutableListOf()

    var phase: SecretHitlerPhase = SecretHitlerPhase.LOBBY

    var presidentId: String? = null; private set
    var chancellorNomineeId: String? = null; private set
    var chancellorId: String? = null; private set
    var previousPresidentId: String? = null; private set
    var previousChancellorId: String? = null; private set
    var specialElectionResumeAfter: String? = null; private set

    var electionTracker: Int = 0; private set
    var liberalPolicies: Int = 0; private set
    var fascistPolicies: Int = 0; private set
    var vetoUnlocked: Boolean = false; private set
    var vetoRequested: Boolean = false; private set

    val drawPile: MutableList<SecretHitlerPolicy> = mutableListOf()
    val discardPile: MutableList<SecretHitlerPolicy> = mutableListOf()
    var presidentialHand: List<SecretHitlerPolicy> = emptyList(); private set
    var chancellorHand: List<SecretHitlerPolicy> = emptyList(); private set

    val electionVotes: MutableMap<String, Boolean> = mutableMapOf()
    var lastElectionPassed: Boolean? = null; private set
    var lastEnactedPolicy: SecretHitlerPolicy? = null; private set
    var lastEnactedByChaos: Boolean = false; private set
    var lastExecutedId: String? = null; private set
    var peekedPolicies: List<SecretHitlerPolicy> = emptyList(); private set
    var pendingInvestigationId: String? = null; private set
    var lastInvestigation: SecretHitlerInvestigation? = null; private set
    val investigatedIds: MutableSet<String> = mutableSetOf()

    var winner: SecretHitlerWinner? = null
    var winReason: SecretHitlerWinReason? = null

    fun addPlayer(id: String, name: String, isHost: Boolean = false): SecretHitlerPlayer {
        val p = SecretHitlerPlayer(id, name, isHost)
        players[id] = p
        if (id !in seatOrder) seatOrder.add(id)
        return p
    }

    fun removePlayer(id: String) {
        if (phase != SecretHitlerPhase.LOBBY) return
        players.remove(id); seatOrder.remove(id)
    }

    val canStart: Boolean
        get() = phase == SecretHitlerPhase.LOBBY && players.size in 5..10

    val alive: List<SecretHitlerPlayer>
        get() = seatOrder.mapNotNull { players[it] }.filter { it.alive }

    fun start() {
        if (!canStart) return
        assignRoles()
        buildDeck()
        seatOrder.shuffle(rng)
        presidentId = seatOrder.firstOrNull()
        phase = SecretHitlerPhase.NOMINATION
    }

    private fun assignRoles() {
        val n = seatOrder.size
        val liberalCount = when (n) { 5 -> 3; 6 -> 4; 7 -> 4; 8 -> 5; 9 -> 5; 10 -> 6; else -> 3 }
        val fascistCount = n - liberalCount - 1
        val roles = MutableList(liberalCount) { SecretHitlerRole.LIBERAL } +
                    MutableList(fascistCount) { SecretHitlerRole.FASCIST } +
                    listOf(SecretHitlerRole.HITLER)
        val shuffled = roles.toMutableList().also { it.shuffle(rng) }
        for ((i, pid) in seatOrder.withIndex()) players[pid]?.role = shuffled[i]
    }

    private fun buildDeck() {
        val deck = MutableList(6) { SecretHitlerPolicy.LIBERAL } +
                   MutableList(11) { SecretHitlerPolicy.FASCIST }
        val shuffled = deck.toMutableList().also { it.shuffle(rng) }
        drawPile.clear(); drawPile.addAll(shuffled)
        discardPile.clear()
    }

    /** Fascists know each other & Hitler. Hitler only knows fascists in 5–6 player games. */
    fun knownAllies(playerId: String): List<String> {
        val me = players[playerId] ?: return emptyList()
        val role = me.role ?: return emptyList()
        val n = seatOrder.size
        return when (role) {
            SecretHitlerRole.LIBERAL -> emptyList()
            SecretHitlerRole.FASCIST -> seatOrder.filter { id ->
                id != playerId && players[id]?.role.let { it == SecretHitlerRole.FASCIST || it == SecretHitlerRole.HITLER }
            }
            SecretHitlerRole.HITLER -> if (n >= 7) emptyList() else seatOrder.filter { id ->
                id != playerId && players[id]?.role == SecretHitlerRole.FASCIST
            }
        }
    }

    fun eligibleChancellorNominees(): List<SecretHitlerPlayer> {
        val aliveCount = alive.size
        return alive.filter { p ->
            p.id != presidentId &&
            p.id != previousChancellorId &&
            !(aliveCount > 5 && p.id == previousPresidentId)
        }
    }

    fun nominateChancellor(targetId: String): Boolean {
        if (phase != SecretHitlerPhase.NOMINATION) return false
        if (eligibleChancellorNominees().none { it.id == targetId }) return false
        chancellorNomineeId = targetId
        electionVotes.clear()
        phase = SecretHitlerPhase.ELECTION
        return true
    }

    fun submitVote(voterId: String, ja: Boolean): Boolean {
        if (phase != SecretHitlerPhase.ELECTION) return false
        val v = players[voterId] ?: return false
        if (!v.alive) return false
        electionVotes[voterId] = ja
        return electionVotes.size >= alive.size
    }

    fun resolveElection(): Boolean {
        if (phase != SecretHitlerPhase.ELECTION) return false
        val yes = electionVotes.values.count { it }
        val no = electionVotes.values.count { !it }
        val passed = yes > no
        lastElectionPassed = passed
        if (passed) {
            previousPresidentId = presidentId
            previousChancellorId = chancellorNomineeId
            chancellorId = chancellorNomineeId
            electionTracker = 0
            val cid = chancellorId
            if (fascistPolicies >= 3 && cid != null && players[cid]?.role == SecretHitlerRole.HITLER) {
                winner = SecretHitlerWinner.FASCIST
                winReason = SecretHitlerWinReason.HITLER_ELECTED_CHANCELLOR
                phase = SecretHitlerPhase.GAME_OVER
                return true
            }
            dealPresidentialHand()
            phase = SecretHitlerPhase.PRESIDENT_DISCARD
            return true
        }
        chancellorNomineeId = null
        chancellorId = null
        electionTracker += 1
        if (electionTracker >= 3) triggerChaos()
        else { advancePresident(); phase = SecretHitlerPhase.NOMINATION }
        return false
    }

    private fun dealPresidentialHand() {
        ensureDeckHasAtLeast(3)
        presidentialHand = drawPile.subList(0, 3).toList()
        repeat(3) { drawPile.removeAt(0) }
    }

    fun presidentDiscard(index: Int): Boolean {
        if (phase != SecretHitlerPhase.PRESIDENT_DISCARD) return false
        if (index !in presidentialHand.indices) return false
        val hand = presidentialHand.toMutableList()
        discardPile.add(hand.removeAt(index))
        chancellorHand = hand
        presidentialHand = emptyList()
        vetoRequested = false
        phase = SecretHitlerPhase.CHANCELLOR_ENACT
        return true
    }

    fun chancellorEnact(index: Int): Boolean {
        if (phase != SecretHitlerPhase.CHANCELLOR_ENACT) return false
        if (index !in chancellorHand.indices) return false
        val hand = chancellorHand.toMutableList()
        val played = hand.removeAt(index)
        discardPile.addAll(hand)
        chancellorHand = emptyList()
        enact(played, byChaos = false)
        return true
    }

    fun chancellorRequestVeto(): Boolean {
        if (phase != SecretHitlerPhase.CHANCELLOR_ENACT || !vetoUnlocked) return false
        vetoRequested = true
        phase = SecretHitlerPhase.VETO_DECISION
        return true
    }

    fun presidentVetoResponse(confirm: Boolean): Boolean {
        if (phase != SecretHitlerPhase.VETO_DECISION) return false
        if (confirm) {
            discardPile.addAll(chancellorHand)
            chancellorHand = emptyList()
            vetoRequested = false
            electionTracker += 1
            if (electionTracker >= 3) triggerChaos()
            else { advancePresident(); phase = SecretHitlerPhase.NOMINATION }
        } else {
            vetoRequested = false
            phase = SecretHitlerPhase.CHANCELLOR_ENACT
        }
        return true
    }

    private fun enact(policy: SecretHitlerPolicy, byChaos: Boolean) {
        lastEnactedPolicy = policy
        lastEnactedByChaos = byChaos
        if (policy == SecretHitlerPolicy.LIBERAL) liberalPolicies += 1 else fascistPolicies += 1
        if (fascistPolicies >= 5) vetoUnlocked = true

        if (liberalPolicies >= 5) {
            winner = SecretHitlerWinner.LIBERAL
            winReason = SecretHitlerWinReason.FIVE_LIBERAL_POLICIES
            phase = SecretHitlerPhase.GAME_OVER
            return
        }
        if (fascistPolicies >= 6) {
            winner = SecretHitlerWinner.FASCIST
            winReason = SecretHitlerWinReason.SIX_FASCIST_POLICIES
            phase = SecretHitlerPhase.GAME_OVER
            return
        }
        if (!byChaos && policy == SecretHitlerPolicy.FASCIST) {
            val p = presidentialPower()
            if (p != null) { enterPower(p); return }
        }
        advancePresident()
        phase = SecretHitlerPhase.NOMINATION
    }

    enum class Power { PEEK, INVESTIGATE, SPECIAL_ELECTION, EXECUTION }

    private fun presidentialPower(): Power? {
        return when (seatOrder.size) {
            5, 6 -> when (fascistPolicies) {
                3 -> Power.PEEK; 4, 5 -> Power.EXECUTION; else -> null
            }
            7, 8 -> when (fascistPolicies) {
                2 -> Power.INVESTIGATE; 3 -> Power.SPECIAL_ELECTION
                4, 5 -> Power.EXECUTION; else -> null
            }
            9, 10 -> when (fascistPolicies) {
                1, 2 -> Power.INVESTIGATE; 3 -> Power.SPECIAL_ELECTION
                4, 5 -> Power.EXECUTION; else -> null
            }
            else -> null
        }
    }

    private fun enterPower(p: Power) {
        when (p) {
            Power.PEEK -> {
                ensureDeckHasAtLeast(3)
                peekedPolicies = drawPile.subList(0, 3).toList()
                phase = SecretHitlerPhase.POLICY_PEEK
            }
            Power.INVESTIGATE -> phase = SecretHitlerPhase.INVESTIGATION
            Power.SPECIAL_ELECTION -> phase = SecretHitlerPhase.SPECIAL_ELECTION
            Power.EXECUTION -> phase = SecretHitlerPhase.EXECUTION
        }
    }

    fun acknowledgePeek(): Boolean {
        if (phase != SecretHitlerPhase.POLICY_PEEK) return false
        peekedPolicies = emptyList()
        advancePresident()
        phase = SecretHitlerPhase.NOMINATION
        return true
    }

    fun investigationTargets(): List<SecretHitlerPlayer> =
        alive.filter { it.id != presidentId && it.id !in investigatedIds }

    fun investigate(targetId: String): Boolean {
        if (phase != SecretHitlerPhase.INVESTIGATION) return false
        val t = players[targetId] ?: return false
        if (!t.alive || t.id == presidentId || t.id in investigatedIds) return false
        pendingInvestigationId = targetId
        lastInvestigation = SecretHitlerInvestigation(targetId, t.role?.party ?: SecretHitlerParty.LIBERAL)
        investigatedIds.add(targetId)
        phase = SecretHitlerPhase.INVESTIGATION_REVEAL
        return true
    }

    fun acknowledgeInvestigation(): Boolean {
        if (phase != SecretHitlerPhase.INVESTIGATION_REVEAL) return false
        pendingInvestigationId = null
        advancePresident()
        phase = SecretHitlerPhase.NOMINATION
        return true
    }

    fun callSpecialElection(targetId: String): Boolean {
        if (phase != SecretHitlerPhase.SPECIAL_ELECTION) return false
        val t = players[targetId] ?: return false
        if (!t.alive || t.id == presidentId) return false
        specialElectionResumeAfter = presidentId
        presidentId = targetId
        chancellorNomineeId = null
        chancellorId = null
        phase = SecretHitlerPhase.NOMINATION
        return true
    }

    fun executionTargets(): List<SecretHitlerPlayer> =
        alive.filter { it.id != presidentId }

    fun executePlayer(targetId: String): Boolean {
        if (phase != SecretHitlerPhase.EXECUTION) return false
        val t = players[targetId] ?: return false
        if (!t.alive || t.id == presidentId) return false
        t.alive = false
        lastExecutedId = targetId
        if (t.role == SecretHitlerRole.HITLER) {
            winner = SecretHitlerWinner.LIBERAL
            winReason = SecretHitlerWinReason.HITLER_EXECUTED
            phase = SecretHitlerPhase.GAME_OVER
            return true
        }
        if (previousChancellorId == targetId) previousChancellorId = null
        if (previousPresidentId == targetId) previousPresidentId = null
        advancePresident()
        phase = SecretHitlerPhase.NOMINATION
        return true
    }

    private fun advancePresident() {
        val resume = specialElectionResumeAfter
        if (resume != null) {
            specialElectionResumeAfter = null
            presidentId = nextAlive(resume)
        } else {
            presidentId?.let { presidentId = nextAlive(it) }
        }
        chancellorNomineeId = null
        chancellorId = null
    }

    private fun nextAlive(from: String): String? {
        val idx = seatOrder.indexOf(from).takeIf { it >= 0 } ?: return alive.firstOrNull()?.id
        val n = seatOrder.size
        for (offset in 1..n) {
            val cand = seatOrder[(idx + offset) % n]
            val p = players[cand]
            if (p != null && p.alive) return cand
        }
        return null
    }

    private fun triggerChaos() {
        ensureDeckHasAtLeast(1)
        val top = drawPile.removeAt(0)
        enact(top, byChaos = true)
        if (phase == SecretHitlerPhase.GAME_OVER) return
        electionTracker = 0
        previousChancellorId = null
        previousPresidentId = null
    }

    private fun ensureDeckHasAtLeast(k: Int) {
        if (drawPile.size >= k) return
        val combined = (drawPile + discardPile).toMutableList()
        combined.shuffle(rng)
        drawPile.clear(); drawPile.addAll(combined)
        discardPile.clear()
    }
}
