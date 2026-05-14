package com.example.ubapp.tutorials

/** One short page in a tutorial. */
data class TutorialSection(val heading: String, val body: String) {
    fun toJson(): Map<String, String> = mapOf("heading" to heading, "body" to body)
}

/** One game's tutorial: title + ordered sections, plus optional
 *  browser-side menu sections shown only to web guests. */
data class GameTutorial(
    val title: String,
    val sections: List<TutorialSection>,
    val browserMenuSections: List<TutorialSection> = emptyList(),
) {
    fun sectionsJson(): List<Map<String, String>> = sections.map { it.toJson() }
    fun browserMenuSectionsJson(): List<Map<String, String>> = browserMenuSections.map { it.toJson() }
}

/** Static tutorial content for every game. Mirrors tutorial_content.dart. */
object GameTutorials {
    val mafia = GameTutorial(
        title = "How to play Mafia",
        sections = listOf(
            TutorialSection("Setup", "Every player gets a secret role: Mafia, Doctor, or Villager. Mafia know each other; the rest of the town does not."),
            TutorialSection("Night", "Mafia secretly pick one player to kill. The Doctor secretly picks one player to save (and may self-save once per game)."),
            TutorialSection("Day", "Everyone learns who died. The whole town discusses and votes to eliminate one suspect. Majority is required to lynch."),
            TutorialSection("Winning", "Town wins if all Mafia are eliminated. Mafia win when they equal or outnumber the remaining town."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Your role", "When the game starts a colored card shows your role at the top of the screen. Keep your phone face-down between turns."),
            TutorialSection("Acting at night", "If you have a night ability you will see a target list. Tap a player to highlight them, then tap Confirm. You can only submit once per night."),
            TutorialSection("Day vote", "Tap the player you want to lynch (or Skip vote), then tap Lock in vote. The day resolves once everyone has voted."),
        ),
    )

    val werewolf = GameTutorial(
        title = "How to play Werewolf",
        sections = listOf(
            TutorialSection("Roles", "Werewolves hunt the village at night and know each other. The Seer privately learns whether one player is a werewolf each night. The Hunter takes one player down with them when killed. Everyone else is a Villager."),
            TutorialSection("Night", "Werewolves coordinate to pick a victim. The Seer picks a player to investigate and privately learns their alignment."),
            TutorialSection("Day", "Reveal who died, then the village discusses and votes to lynch a suspect. Majority lynches."),
            TutorialSection("Hunter shot", "If a Hunter dies (night or day), the game pauses and they pick one player to take with them. If that player is also a Hunter, the chain continues."),
            TutorialSection("Winning", "Village wins if all Werewolves are eliminated. Werewolves win when they equal or outnumber the rest."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Your role", "A colored card at the top reveals your role. Werewolves also see a list of their fellow wolves."),
            TutorialSection("Night actions", "Werewolves and the Seer see a target list at night. Tap a player, then Confirm. The Seer's findings are listed in a Seer findings card visible only to the Seer."),
            TutorialSection("Hunter shot", "If you are the Hunter and you die, you will see a \"Take one with you\" prompt. Tap a player, then Fire."),
            TutorialSection("Day vote", "Tap a suspect (or Skip vote), then Lock in vote. Resolves when everyone alive has voted."),
        ),
    )

    val imposter = GameTutorial(
        title = "How to play Imposter",
        sections = listOf(
            TutorialSection("Setup", "One player is secretly the Imposter. Everyone else is a townie. Townies see a category AND a secret word. The Imposter sees only the category."),
            TutorialSection("Discussion", "Take turns asking each other questions about the word — vague enough that you do not give it away, specific enough to prove you actually know it."),
            TutorialSection("Vote", "When you are ready, vote on who you think is the Imposter. The most-voted player is revealed."),
            TutorialSection("Winning", "Townies win if they correctly vote out the Imposter. The Imposter wins if a townie is voted out instead."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Your card", "A big card shows your secret word and category — or \"IMPOSTER\" and just the category if you are the bluffer. Memorise it, then hide your phone."),
            TutorialSection("Discussion", "There are no on-screen actions while you talk. Ask each other questions in person. The host will call a vote when the table is ready."),
            TutorialSection("Voting", "A list of every other player appears. Tap one (or Skip), then Lock in vote. You cannot change your vote after."),
        ),
    )

    val codenames = GameTutorial(
        title = "How to play Codenames",
        sections = listOf(
            TutorialSection("Setup", "Two teams (red and blue). Each team picks one Spymaster who sees which words belong to which team, plus an Assassin word and neutral words."),
            TutorialSection("Clues", "On your turn, the Spymaster gives a one-word clue and a number — e.g. \"Animal 3\". The clue must relate to that many of your team's words on the board."),
            TutorialSection("Guessing", "Operatives discuss and tap words. A correct word stays on your team. A neutral or enemy word ends your turn. The Assassin ends the game — your team loses immediately."),
            TutorialSection("Winning", "First team to reveal all of their words wins."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Joining a team", "In the lobby tap Join Red or Join Blue. Then tap Be Spymaster if you want to give clues — each team needs exactly one. The host starts when both teams are ready."),
            TutorialSection("Spymaster view", "Spymasters see a coloured outline on every card showing its allegiance (your colour, the enemy's, neutral, or the assassin). Do NOT show your phone to your team."),
            TutorialSection("Giving a clue", "When it is your turn as Spymaster type a one-word clue and a number, then send. Operatives discuss out loud and tap cards to guess; the Spymaster cannot tap."),
            TutorialSection("Guessing", "Operatives tap a word card to reveal it. Correct cards stay your colour. A wrong card ends your turn. Tap End turn early if you want to stop guessing."),
        ),
    )

    val crazyEights = GameTutorial(
        title = "How to play Crazy Eights",
        sections = listOf(
            TutorialSection("Deal", "Each player is dealt a hand of cards from a standard 52-card deck. The top of the deck flips up as the discard pile."),
            TutorialSection("Your turn", "Play a card matching the suit or rank on top of the discard. If you cannot, draw from the deck until you can play."),
            TutorialSection("Eights are wild", "You can play an 8 on anything, and you choose the new suit the next player must follow."),
            TutorialSection("Winning", "First player to empty their hand wins the round."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Your hand", "Your cards are along the bottom of the screen. Playable cards are highlighted; unplayable ones look faded."),
            TutorialSection("Playing a card", "Tap a card to select it (it turns purple), then tap the Play button that appears. If you played an 8, a popup asks you to declare the new active suit."),
            TutorialSection("Drawing & passing", "If you cannot play, tap the draw pile on the left of the table. If the new card is playable you can still play it; otherwise tap Pass to end your turn."),
        ),
    )

    val tag = GameTutorial(
        title = "How to play Tag (BLE proximity)",
        sections = listOf(
            TutorialSection("Pair up", "Every phone running the app advertises a BLE beacon and scans for nearby phones. Stay within a few meters of each other for the proximity detector to pick you up."),
            TutorialSection("It and not-it", "One player is \"It\" (highlighted red). Get close to a not-It player to tag them and pass It along."),
            TutorialSection("Variants", "Try Freeze Tag (tagged players freeze until rescued), Infection (tagged players also become It), or Sharks & Minnows. Pick one in the lobby before starting."),
            TutorialSection("Have fun", "No phones-in-pockets cheating. Hold the device where the antenna can breathe."),
        ),
    )

    val ticTacToe = GameTutorial(
        title = "How to play Tic-Tac-Toe",
        sections = listOf(
            TutorialSection("Goal", "Get three of your marks in a row — horizontally, vertically, or diagonally."),
            TutorialSection("Turns", "You are X, the AI is O. Tap an empty cell to play. The AI uses a perfect-play search, so your best result against it is a draw."),
        ),
    )

    val connectFour = GameTutorial(
        title = "How to play Connect Four",
        sections = listOf(
            TutorialSection("Goal", "Drop discs into the columns. First to line up four discs in a row, column, or diagonal wins."),
            TutorialSection("Turns", "Tap a column to drop your disc. The AI alternates with you. The center column tends to be the strongest opener."),
        ),
    )

    val realTime = GameTutorial(
        title = "How to play Real-time",
        sections = listOf(
            TutorialSection("Movement", "Drag on the screen to move your player around the arena."),
            TutorialSection("Enemies", "Four AI enemies wander around. When you get close, they switch to Chase mode and come after you. Stay just far enough away to keep them wandering."),
        ),
    )

    fun byKey(key: String): GameTutorial? = when (key) {
        "mafia" -> mafia
        "werewolf" -> werewolf
        "imposter" -> imposter
        "codenames" -> codenames
        "crazy_eights" -> crazyEights
        "tag" -> tag
        "tic_tac_toe" -> ticTacToe
        "connect_four" -> connectFour
        "real_time" -> realTime
        else -> null
    }
}
