package com.example.ubapp.games.imposter

import kotlin.random.Random

enum class ImposterPhase { LOBBY, PLAYING, VOTING, RESULT, GAME_OVER }
enum class ImposterWinner { TOWN, IMPOSTER }

class ImposterPlayer(val id: String, val name: String, val isHost: Boolean) {
    var isImposter: Boolean = false
}

class ImposterEngine(private val rng: Random = Random.Default) {
    val players: MutableMap<String, ImposterPlayer> = linkedMapOf()
    var phase: ImposterPhase = ImposterPhase.LOBBY

    var category: String = ""
    var secretWord: String = ""
    var imposterId: String? = null

    val votes: MutableMap<String, String?> = mutableMapOf()
    var mostVotedId: String? = null
    var imposterCaught: Boolean? = null
    var winner: ImposterWinner? = null

    fun addPlayer(id: String, name: String, isHost: Boolean = false): ImposterPlayer {
        val p = ImposterPlayer(id, name, isHost); players[id] = p; return p
    }
    fun removePlayer(id: String) { if (phase == ImposterPhase.LOBBY) players.remove(id) }
    val canStart: Boolean get() = phase == ImposterPhase.LOBBY && players.size >= 3
    val availableCategories: Set<String> get() = ImposterWords.categories.keys

    fun start(categoryName: String? = null) {
        if (!canStart) return
        val cats = ImposterWords.categories.keys.toList()
        category = categoryName?.takeIf { ImposterWords.categories.containsKey(it) }
            ?: cats[rng.nextInt(cats.size)]
        val words = ImposterWords.categories[category]!!
        secretWord = words[rng.nextInt(words.size)]
        val ids = players.keys.toList()
        imposterId = ids[rng.nextInt(ids.size)]
        for (p in players.values) p.isImposter = (p.id == imposterId)
        phase = ImposterPhase.PLAYING
    }

    fun beginVoting() {
        if (phase != ImposterPhase.PLAYING) return
        votes.clear()
        phase = ImposterPhase.VOTING
    }

    fun submitVote(voterId: String, targetId: String?): Boolean {
        if (phase != ImposterPhase.VOTING) return false
        if (!players.containsKey(voterId)) return false
        if (targetId != null && !players.containsKey(targetId)) return false
        votes[voterId] = targetId
        return votes.size == players.size
    }

    fun resolveVotes() {
        val tally = mutableMapOf<String, Int>()
        for (v in votes.values) if (v != null) tally[v] = (tally[v] ?: 0) + 1
        var max = 0; val tied = mutableListOf<String>()
        for ((id, c) in tally) {
            if (c > max) { max = c; tied.clear(); tied.add(id) }
            else if (c == max) tied.add(id)
        }
        mostVotedId = if (tied.size == 1) tied[0] else null
        imposterCaught = mostVotedId == imposterId
        winner = if (imposterCaught == true) ImposterWinner.TOWN else ImposterWinner.IMPOSTER
        phase = ImposterPhase.RESULT
    }

    fun reset() {
        phase = ImposterPhase.LOBBY
        category = ""; secretWord = ""; imposterId = null
        votes.clear(); mostVotedId = null; imposterCaught = null; winner = null
        for (p in players.values) p.isImposter = false
    }
}

object ImposterWords {
    // TODO: full word list ported from lib/games/imposter/imposter_words.dart
    val categories: Map<String, List<String>> = mapOf(
        "Locations" to listOf("Beach", "Library", "Casino", "Spaceship", "Hospital"),
        "Animals" to listOf("Lion", "Penguin", "Octopus", "Kangaroo", "Hawk"),
        "Foods" to listOf("Sushi", "Tacos", "Lasagna", "Falafel", "Dumplings"),
    )
}
