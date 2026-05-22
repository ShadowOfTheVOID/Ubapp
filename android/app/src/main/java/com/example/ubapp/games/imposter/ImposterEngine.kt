package com.example.ubapp.games.imposter

import kotlin.random.Random

enum class ImposterPhase { LOBBY, PLAYING, VOTING, RESULT, GAME_OVER }
enum class ImposterWinner { TOWN, IMPOSTER }

/** Host-configurable knobs. Defaults reproduce the classic single-imposter
 *  game so an unconfigured session plays exactly like before this struct
 *  existed. */
data class ImposterOptions(
    val imposterCount: Int = 1,
    val decoyWord: Boolean = false,
    val hideCategory: Boolean = false,
    val mixedPool: Boolean = false,
)

class ImposterPlayer(val id: String, val name: String, val isHost: Boolean) {
    var isImposter: Boolean = false
    var decoyWord: String? = null
}

class ImposterEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, ImposterPlayer> = linkedMapOf()
    var phase: ImposterPhase = ImposterPhase.LOBBY
    var options: ImposterOptions = ImposterOptions()
        private set

    var category: String = ""
    var secretWord: String = ""
    var imposterIds: Set<String> = emptySet()
    /** Last round's imposter line-up, used to avoid handing the role to the
     *  exact same people two rounds running. Survives [reset] on purpose. */
    private var lastImposterIds: Set<String> = emptySet()

    /** Player who gives the first clue, and the direction play proceeds
     *  around the room. Chosen at round start so everyone agrees on order. */
    var firstPlayerId: String? = null
    var clockwise: Boolean = true

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
    val maxImposterCount: Int get() = maxOf(1, players.size - 1)

    fun setOptions(o: ImposterOptions) {
        if (phase != ImposterPhase.LOBBY) return
        options = o.copy(
            imposterCount = o.imposterCount.coerceIn(1, maxOf(1, players.size - 1))
        )
    }

    fun start(categoryName: String? = null) {
        if (!canStart) return
        val cats = ImposterWords.categories.keys.toList()
        if (options.mixedPool) {
            category = "Mixed"
            val pool = ImposterWords.categories.values.flatten()
            secretWord = pool[rng.nextInt(pool.size)]
        } else {
            category = categoryName?.takeIf { ImposterWords.categories.containsKey(it) }
                ?: cats[rng.nextInt(cats.size)]
            val words = ImposterWords.categories[category]!!
            secretWord = words[rng.nextInt(words.size)]
        }
        val ids = players.keys.toList().shuffled(rng)
        val count = options.imposterCount.coerceIn(1, maxOf(1, ids.size - 1))
        var chosen = ids.take(count).toSet()
        // Don't repeat the exact same imposter line-up two rounds in a row
        // when the lobby is big enough to pick someone else — swapping one
        // member guarantees a different set in a single deterministic step.
        if (chosen == lastImposterIds && ids.size > count) {
            chosen = chosen - ids[0] + ids[count]
        }
        imposterIds = chosen
        lastImposterIds = chosen
        firstPlayerId = ids[rng.nextInt(ids.size)]
        clockwise = rng.nextInt(2) == 0
        for (p in players.values) {
            p.isImposter = p.id in imposterIds
            p.decoyWord = null
            if (p.isImposter && options.decoyWord) {
                val pool = if (options.mixedPool)
                    ImposterWords.categories.values.flatten()
                else
                    ImposterWords.categories[category].orEmpty()
                val alternatives = pool.filter { it != secretWord }
                if (alternatives.isNotEmpty()) {
                    p.decoyWord = alternatives[rng.nextInt(alternatives.size)]
                }
            }
        }
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
        imposterCaught = mostVotedId?.let { it in imposterIds }
        winner = if (imposterCaught == true) ImposterWinner.TOWN else ImposterWinner.IMPOSTER
        phase = ImposterPhase.RESULT
    }

    fun reset() {
        phase = ImposterPhase.LOBBY
        category = ""; secretWord = ""; imposterIds = emptySet()
        firstPlayerId = null; clockwise = true
        votes.clear(); mostVotedId = null; imposterCaught = null; winner = null
        for (p in players.values) { p.isImposter = false; p.decoyWord = null }
    }
}

object ImposterWords {
    /** Built-in word categories. Each category gets a list of secret words
     *  that all townspeople see; the imposter sees only the category name. */
    val categories: Map<String, List<String>> = mapOf(
        "Food" to listOf(
            "pizza", "sushi", "taco", "burger", "ramen", "cake", "ice cream",
            "pasta", "pancake", "sandwich", "curry", "salad", "soup", "bagel",
            "doughnut", "fries", "omelette", "lasagna", "kebab", "risotto",
        ),
        "Animal" to listOf(
            "dog", "cat", "elephant", "dolphin", "eagle", "snake", "panda",
            "lion", "tiger", "rabbit", "shark", "octopus", "penguin", "horse",
            "kangaroo", "sloth", "owl", "wolf", "fox", "bear",
        ),
        "Place" to listOf(
            "beach", "forest", "desert", "mountain", "city", "farm", "school",
            "hospital", "airport", "library", "museum", "theater", "park",
            "subway", "castle", "casino", "restaurant", "gym", "church", "bridge",
        ),
        "Movie" to listOf(
            "Star Wars", "Titanic", "Inception", "Avatar", "The Matrix", "Frozen",
            "Avengers", "Toy Story", "Jaws", "Up", "Coco", "Shrek", "Rocky",
            "Gladiator", "Interstellar", "Pulp Fiction", "The Godfather", "Joker",
            "La La Land", "Parasite",
        ),
        "Sport" to listOf(
            "soccer", "basketball", "tennis", "baseball", "hockey", "cricket",
            "golf", "rugby", "volleyball", "swimming", "cycling", "boxing",
            "fencing", "archery", "skiing", "surfing", "climbing", "judo",
            "rowing", "badminton",
        ),
    )
}
