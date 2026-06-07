package com.example.jamboree.games.codenames

import kotlin.random.Random

enum class Team { RED, BLUE; val other: Team get() = if (this == RED) BLUE else RED; val name2 get() = name.lowercase() }
enum class CardKind { RED, BLUE, NEUTRAL, ASSASSIN }
enum class CodenamesPhase { LOBBY, PLAYING, GAME_OVER }

/** Host-configurable knobs. Defaults reproduce the 25-card / 1-assassin classic. */
data class CodenamesOptions(
    val boardSize: Int = 25,
    val assassinCount: Int = 1,
) {
    companion object {
        val allowedSizes = listOf(16, 25, 36)
    }
}

class CodenamesCard(val word: String, val kind: CardKind) { var revealed: Boolean = false }
class CodenamesPlayer(val id: String, val name: String, val isHost: Boolean) {
    var team: Team? = null
    var isSpymaster: Boolean = false
}

class CodenamesEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.jamboree.tutorials.TutorialVote()
    val players: MutableMap<String, CodenamesPlayer> = linkedMapOf()
    var phase: CodenamesPhase = CodenamesPhase.LOBBY
    var options: CodenamesOptions = CodenamesOptions()
        private set

    val board: MutableList<CodenamesCard> = mutableListOf()
    var startingTeam: Team = Team.RED
    var currentTeam: Team = Team.RED
    var currentClue: String? = null
    var currentNumber: Int = 0
    var guessesLeftThisTurn: Int = 0
    var winner: Team? = null
    var endReason: String? = null
    var lastEvent: String? = null

    fun addPlayer(id: String, name: String, isHost: Boolean = false): CodenamesPlayer {
        val p = CodenamesPlayer(id, name, isHost); players[id] = p; return p
    }
    fun removePlayer(id: String) { if (phase == CodenamesPhase.LOBBY) players.remove(id) }
    fun setTeam(id: String, team: Team) {
        if (phase != CodenamesPhase.LOBBY) return
        players[id]?.team = team
    }
    fun setSpymaster(id: String, isSpymaster: Boolean) {
        if (phase != CodenamesPhase.LOBBY) return
        val p = players[id] ?: return
        if (isSpymaster && p.team != null) {
            for (other in players.values) if (other.id != id && other.team == p.team) other.isSpymaster = false
        }
        p.isSpymaster = isSpymaster
    }

    val canStart: Boolean get() {
        if (phase != CodenamesPhase.LOBBY) return false
        if (players.size < 4) return false
        val red = players.values.filter { it.team == Team.RED }
        val blue = players.values.filter { it.team == Team.BLUE }
        if (red.size < 2 || blue.size < 2) return false
        if (red.none { it.isSpymaster } || blue.none { it.isSpymaster }) return false
        return true
    }

    fun setOptions(o: CodenamesOptions) {
        if (phase != CodenamesPhase.LOBBY) return
        options = o.copy(
            boardSize = if (o.boardSize in CodenamesOptions.allowedSizes) o.boardSize else 25,
            assassinCount = o.assassinCount.coerceIn(1, 3),
        )
    }

    fun start() {
        if (!canStart) return
        val pool = CodenamesWords.bank.toMutableList().also { it.shuffle(rng) }
        val n = options.boardSize
        val words = pool.take(n)
        startingTeam = if (rng.nextBoolean()) Team.RED else Team.BLUE
        currentTeam = startingTeam
        val assassins = options.assassinCount
        val neutrals = (n * 7) / 25
        val teamCards = n - neutrals - assassins
        val startCount = (teamCards + 1) / 2
        val otherCount = teamCards - startCount
        val kinds: MutableList<CardKind> = mutableListOf<CardKind>().apply {
            repeat(if (startingTeam == Team.RED) startCount else otherCount) { add(CardKind.RED) }
            repeat(if (startingTeam == Team.BLUE) startCount else otherCount) { add(CardKind.BLUE) }
            repeat(neutrals) { add(CardKind.NEUTRAL) }
            repeat(assassins) { add(CardKind.ASSASSIN) }
        }
        kinds.shuffle(rng)
        board.clear()
        for (i in 0 until n) board.add(CodenamesCard(words[i], kinds[i]))

        phase = CodenamesPhase.PLAYING
        currentClue = null; currentNumber = 0; guessesLeftThisTurn = 0
        winner = null; endReason = null
        lastEvent = "Game begins. ${currentTeam.name2.uppercase()} spymaster, give the first clue."
    }

    fun submitClue(spymasterId: String, clue: String, number: Int): Boolean {
        if (phase != CodenamesPhase.PLAYING) return false
        val p = players[spymasterId] ?: return false
        if (!p.isSpymaster || p.team != currentTeam) return false
        if (currentClue != null) return false
        val trimmed = clue.trim()
        if (trimmed.isEmpty()) return false
        // Clamp the guest-supplied number: a huge value removes the guess cap
        // (cheat) and a negative one freezes the turn (DoS). A clue can never
        // exceed the cards on the board.
        val n = number.coerceIn(0, board.size)
        currentClue = trimmed; currentNumber = n; guessesLeftThisTurn = n + 1
        lastEvent = "${p.name} (${currentTeam.name2}) clue: \"$trimmed\" $n"
        return true
    }

    fun guess(guesserId: String, boardIndex: Int): CardKind? {
        if (phase != CodenamesPhase.PLAYING) return null
        val p = players[guesserId] ?: return null
        if (p.isSpymaster || p.team != currentTeam) return null
        if (currentClue == null || guessesLeftThisTurn <= 0) return null
        if (boardIndex !in 0 until board.size) return null
        val card = board[boardIndex]
        if (card.revealed) return null
        card.revealed = true

        val teamKind = if (currentTeam == Team.RED) CardKind.RED else CardKind.BLUE
        val opponentKind = if (currentTeam == Team.RED) CardKind.BLUE else CardKind.RED

        if (card.kind == CardKind.ASSASSIN) {
            winner = currentTeam.other
            endReason = "${currentTeam.name2.uppercase()} hit the assassin"
            phase = CodenamesPhase.GAME_OVER
            lastEvent = "${p.name} guessed ${card.word} — ASSASSIN. ${winner!!.name2.uppercase()} wins!"
            return card.kind
        }
        lastEvent = "${p.name} guessed ${card.word} (${card.kind.name.lowercase()})"
        when (card.kind) {
            teamKind -> {
                guessesLeftThisTurn -= 1
                if (checkBoardWin()) return card.kind
                if (guessesLeftThisTurn <= 0) endTurnInternal()
            }
            opponentKind -> { if (checkBoardWin()) return card.kind; endTurnInternal() }
            else -> { if (checkBoardWin()) return card.kind; endTurnInternal() }
        }
        return card.kind
    }

    fun endTurn(guesserId: String) {
        if (phase != CodenamesPhase.PLAYING) return
        val p = players[guesserId] ?: return
        if (p.isSpymaster || p.team != currentTeam) return
        if (currentClue == null) return
        if (guessesLeftThisTurn == currentNumber + 1) return
        endTurnInternal()
    }

    private fun endTurnInternal() {
        currentTeam = currentTeam.other
        currentClue = null; currentNumber = 0; guessesLeftThisTurn = 0
        val prefix = lastEvent?.takeIf { it.isNotEmpty() }?.let { "$it. " } ?: ""
        lastEvent = "${prefix}Turn passes to ${currentTeam.name2.uppercase()}."
    }

    private fun checkBoardWin(): Boolean {
        val redLeft = board.count { !it.revealed && it.kind == CardKind.RED }
        val blueLeft = board.count { !it.revealed && it.kind == CardKind.BLUE }
        if (redLeft == 0) { winner = Team.RED; endReason = "red found all their words"; phase = CodenamesPhase.GAME_OVER; return true }
        if (blueLeft == 0) { winner = Team.BLUE; endReason = "blue found all their words"; phase = CodenamesPhase.GAME_OVER; return true }
        return false
    }

    fun cardsLeftFor(team: Team): Int {
        val kind = if (team == Team.RED) CardKind.RED else CardKind.BLUE
        return board.count { !it.revealed && it.kind == kind }
    }

    fun reset() {
        phase = CodenamesPhase.LOBBY
        board.clear()
        currentClue = null; currentNumber = 0; guessesLeftThisTurn = 0
        winner = null; endReason = null; lastEvent = null
    }
}

object CodenamesWords {
    /** Independently-authored, family-friendly bank of common concrete nouns —
     *  pick up to 36 per game. Not derived from any other game's word set. */
    val bank: List<String> = listOf(
        "ACORN", "ANCHOR", "ANTLER", "APRON", "ARROW", "AVALANCHE", "BADGER", "BAGEL",
        "BALLOON", "BAMBOO", "BANANA", "BANJO", "BARREL", "BASKET", "BEACON", "BEAVER",
        "BISCUIT", "BLANKET", "BLIZZARD", "BOULDER", "BREEZE", "BROOM", "BUBBLE", "BUCKET",
        "BUTTON", "CACTUS", "CAMEL", "CANDLE", "CANOE", "CANYON", "CARAMEL", "CARPET",
        "CASTLE", "CAVERN", "CHEETAH", "CHERRY", "CHIMNEY", "CINNAMON", "CLOCK", "CLOUD",
        "COBRA", "COCONUT", "COMET", "COMPASS", "COOKIE", "CORAL", "COSTUME", "COWBOY",
        "CRADLE", "CRAYON", "CROCODILE", "CROW", "CUSHION", "CYMBAL", "DESERT", "DOLPHIN",
        "DOMINO", "DONKEY", "DRAGONFLY", "DRAWER", "DRUM", "DUMPLING", "DUNE", "ECHO",
        "ELBOW", "EMBER", "ENVELOPE", "FALCON", "FEATHER", "FERRET", "FIDDLE", "FIREWORK",
        "FLAMINGO", "FOLDER", "FOSSIL", "FOUNTAIN", "FRECKLE", "FROST", "FUNNEL", "GARLIC",
        "GECKO", "GINGER", "GLACIER", "GOAT", "GOBLIN", "GONDOLA", "GOOSE", "GRAPE",
        "GROVE", "HAMMER", "HAMSTER", "HANGER", "HARBOR", "HARP", "HEDGEHOG", "HELMET",
        "HICCUP", "HORNET", "ICEBERG", "IGLOO", "IGUANA", "JACKET", "JAGUAR", "JELLYFISH",
        "JESTER", "JIGSAW", "JUNGLE", "KAYAK", "KETTLE", "KIMONO", "KITE", "KOALA",
        "LADDER", "LAGOON", "LANTERN", "LASSO", "LAVA", "LENTIL", "LIGHTHOUSE", "LIZARD",
        "LLAMA", "LOBSTER", "LOCKET", "MAGNET", "MANDOLIN", "MANGO", "MARSHMALLOW", "MASK",
        "MAZE", "MEADOW", "MEDAL", "MERMAID", "METEOR", "MITTEN", "MOLE", "MONOCLE",
        "MOOSE", "MOSAIC", "MUFFIN", "MUSHROOM", "NAPKIN", "NEEDLE", "NOODLE", "OATMEAL",
        "OCTOPUS", "OLIVE", "ORCHARD", "ORGAN", "OSTRICH", "OTTER", "OWL", "PADDLE",
        "PANCAKE", "PANDA", "PARADE", "PARROT", "PEACOCK", "PEBBLE", "PELICAN", "PENGUIN",
        "PEPPER", "PICKLE", "PILLOW", "PIRATE", "PISTACHIO", "PLATEAU", "PLIERS", "POPCORN",
        "PRETZEL", "PUDDLE", "PUFFIN", "PUMPKIN", "PUPPET", "PUZZLE", "QUILT", "RABBIT",
        "RACCOON", "RADISH", "RAFT", "RAINBOW", "RANCH", "RAVEN", "REEF", "RIBBON",
        "ROCKET", "SADDLE", "SAILBOAT", "SANDAL", "SCARF", "SCOOTER", "SEASHELL", "SHOVEL",
        "SKATE", "SLED", "SLIPPER", "SLOTH", "SNAIL", "SNOWFLAKE", "SPONGE", "SQUID",
        "STAPLER", "STARFISH", "STORK", "SUITCASE", "SUNFLOWER", "SWAMP", "TACO", "TAMBOURINE",
        "TEAPOT", "TELESCOPE", "TENT", "THIMBLE", "THISTLE", "TOAD", "TORCH", "TORTOISE",
        "TRACTOR", "TRAMPOLINE", "TROMBONE", "TROPHY", "TRUMPET", "TUBA", "TULIP", "TUNDRA",
        "TUNNEL", "TURTLE", "UMBRELLA", "UNICORN", "VALLEY", "VASE", "VIOLIN", "VOLCANO",
        "WAFFLE", "WAGON", "WALNUT", "WALRUS", "WATERFALL", "WEASEL", "WHISTLE", "WINDMILL",
        "WIZARD", "WOMBAT", "WRENCH", "ZEBRA",
    )
}
