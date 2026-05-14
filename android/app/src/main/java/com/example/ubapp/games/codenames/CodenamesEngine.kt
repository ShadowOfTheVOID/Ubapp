package com.example.ubapp.games.codenames

import kotlin.random.Random

enum class Team { RED, BLUE; val other: Team get() = if (this == RED) BLUE else RED; val name2 get() = name.lowercase() }
enum class CardKind { RED, BLUE, NEUTRAL, ASSASSIN }
enum class CodenamesPhase { LOBBY, PLAYING, GAME_OVER }

class CodenamesCard(val word: String, val kind: CardKind) { var revealed: Boolean = false }
class CodenamesPlayer(val id: String, val name: String, val isHost: Boolean) {
    var team: Team? = null
    var isSpymaster: Boolean = false
}

class CodenamesEngine(private val rng: Random = Random.Default) {
    val tutorialVote = com.example.ubapp.tutorials.TutorialVote()
    val players: MutableMap<String, CodenamesPlayer> = linkedMapOf()
    var phase: CodenamesPhase = CodenamesPhase.LOBBY

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

    fun start() {
        if (!canStart) return
        val pool = CodenamesWords.bank.toMutableList().also { it.shuffle(rng) }
        val words = pool.take(25)
        startingTeam = if (rng.nextBoolean()) Team.RED else Team.BLUE
        currentTeam = startingTeam
        val kinds: MutableList<CardKind> = mutableListOf<CardKind>().apply {
            repeat(if (startingTeam == Team.RED) 9 else 8) { add(CardKind.RED) }
            repeat(if (startingTeam == Team.BLUE) 9 else 8) { add(CardKind.BLUE) }
            repeat(7) { add(CardKind.NEUTRAL) }
            add(CardKind.ASSASSIN)
        }
        kinds.shuffle(rng)
        board.clear()
        for (i in 0 until 25) board.add(CodenamesCard(words[i], kinds[i]))

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
        currentClue = trimmed; currentNumber = number; guessesLeftThisTurn = number + 1
        lastEvent = "${p.name} (${currentTeam.name2}) clue: \"$trimmed\" $number"
        return true
    }

    fun guess(guesserId: String, boardIndex: Int): CardKind? {
        if (phase != CodenamesPhase.PLAYING) return null
        val p = players[guesserId] ?: return null
        if (p.isSpymaster || p.team != currentTeam) return null
        if (currentClue == null || guessesLeftThisTurn <= 0) return null
        if (boardIndex !in 0 until 25) return null
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
    /** Family-friendly subset of the standard 400-word Codenames bank — pick 25
     *  per game. */
    val bank: List<String> = listOf(
        "AFRICA", "AGENT", "AIR", "ALIEN", "ALPS", "AMAZON", "AMBULANCE", "ANGEL",
        "ANTARCTICA", "APPLE", "ARM", "ATLANTIS", "AUSTRALIA", "AZTEC", "BACK", "BALL",
        "BAND", "BANK", "BAR", "BARK", "BAT", "BATTERY", "BEACH", "BEAR",
        "BEAT", "BED", "BEIJING", "BELL", "BELT", "BERLIN", "BERMUDA", "BERRY",
        "BILL", "BLOCK", "BOARD", "BOLT", "BOMB", "BOND", "BOOM", "BOOT",
        "BOTTLE", "BOW", "BOX", "BRIDGE", "BRUSH", "BUCK", "BUFFALO", "BUG",
        "BUGLE", "BUTTON", "CALF", "CANADA", "CAP", "CAPITAL", "CAR", "CARD",
        "CARROT", "CASINO", "CAST", "CAT", "CELL", "CENTAUR", "CENTER", "CHAIR",
        "CHANGE", "CHARGE", "CHECK", "CHEST", "CHICK", "CHINA", "CHOCOLATE", "CHURCH",
        "CIRCLE", "CLIFF", "CLOAK", "CLUB", "CODE", "COLD", "COMIC", "COMPOUND",
        "CONCERT", "CONDUCTOR", "CONTRACT", "COOK", "COPPER", "COTTON", "COURT", "COVER",
        "CRANE", "CRASH", "CROSS", "CROWN", "CYCLE", "CZECH", "DANCE", "DATE",
        "DAY", "DEATH", "DECK", "DEGREE", "DIAMOND", "DICE", "DINOSAUR", "DISEASE",
        "DOCTOR", "DOG", "DRAFT", "DRAGON", "DRESS", "DRILL", "DROP", "DUCK",
        "DWARF", "EAGLE", "EGYPT", "EMBASSY", "ENGINE", "ENGLAND", "EUROPE", "EYE",
        "FACE", "FAIR", "FALL", "FAN", "FENCE", "FIELD", "FIGHTER", "FIGURE",
        "FILE", "FILM", "FIRE", "FISH", "FLUTE", "FLY", "FOOT", "FORCE",
        "FOREST", "FORK", "FRANCE", "GAME", "GAS", "GENIUS", "GERMANY", "GHOST",
        "GIANT", "GLASS", "GLOVE", "GOLD", "GRACE", "GRASS", "GREECE", "GREEN",
        "GROUND", "HAM", "HAND", "HAWK", "HEAD", "HEART", "HELICOPTER", "HIMALAYAS",
        "HOLE", "HOLLYWOOD", "HONEY", "HOOD", "HOOK", "HORN", "HORSE", "HORSESHOE",
        "HOSPITAL", "HOTEL", "ICE", "INDIA", "IRON", "IVORY", "JACK", "JAM",
        "JET", "JUPITER", "KANGAROO", "KETCHUP", "KEY", "KID", "KING", "KIWI",
        "KNIFE", "KNIGHT", "LAB", "LADY", "LAP", "LASER", "LAWYER", "LEAD",
        "LEMON", "LEPRECHAUN", "LIFE", "LIGHT", "LIMOUSINE", "LINE", "LINK", "LION",
        "LITTER", "LOCH NESS", "LOCK", "LOG", "LONDON", "LUCK", "MAIL", "MAMMOTH",
        "MAPLE", "MARBLE", "MARCH", "MASS", "MATCH", "MERCURY", "MEXICO", "MICROSCOPE",
        "MILLIONAIRE", "MINE", "MINT", "MISSILE", "MODEL", "MOON", "MOSCOW", "MOUNT",
        "MOUSE", "MOUTH", "MUG", "NAIL",
    )
}
