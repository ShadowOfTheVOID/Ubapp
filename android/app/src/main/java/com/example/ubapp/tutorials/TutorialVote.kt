package com.example.ubapp.tutorials

/**
 * Pure majority-wins yes/no vote used to decide whether a game's pre-game
 * tutorial should be shown. Engines and servers wrap this; it has no I/O.
 */
class TutorialVote {
    var isOpen: Boolean = false; private set
    private val votes: MutableMap<String, Boolean> = mutableMapOf()
    var result: Boolean? = null; private set
    /** Tutorial was actually displayed to players — used to keep the vote
     *  button hidden after the tutorial has already run once. */
    var tutorialShown: Boolean = false; private set
    private val eligibleSet: MutableSet<String> = mutableSetOf()

    val hasResult: Boolean get() = result != null
    val yesCount: Int get() = votes.values.count { it }
    val noCount: Int get() = votes.values.count { !it }
    val eligibleCount: Int get() = eligibleSet.size
    val eligible: Set<String> get() = eligibleSet

    fun markShown() { tutorialShown = true }
    fun isEligible(id: String) = eligibleSet.contains(id)

    /** Reset and open a fresh vote. [eligibleIds] is the snapshot of players
     *  in the lobby when the vote was called. */
    fun open(eligibleIds: Iterable<String>) {
        isOpen = true
        votes.clear()
        result = null
        eligibleSet.clear()
        eligibleSet.addAll(eligibleIds)
    }

    /** Returns true once every eligible voter has submitted — at which point
     *  [result] is finalized. */
    fun submit(voterId: String, yes: Boolean): Boolean {
        if (!isOpen || voterId !in eligibleSet) return false
        votes[voterId] = yes
        if (votes.size >= eligibleSet.size) { finalize(); return true }
        return false
    }

    fun close() { if (isOpen) finalize() }

    /** A voter dropped out (e.g. left the lobby). */
    fun removeVoter(id: String) {
        if (!isOpen) return
        eligibleSet.remove(id)
        votes.remove(id)
        if (eligibleSet.isEmpty()) {
            isOpen = false; votes.clear(); result = null
            return
        }
        if (votes.size >= eligibleSet.size) finalize()
    }

    private fun finalize() {
        // Strict majority — ties resolve to "no" (skip tutorial).
        result = yesCount > noCount
        isOpen = false
    }
}
