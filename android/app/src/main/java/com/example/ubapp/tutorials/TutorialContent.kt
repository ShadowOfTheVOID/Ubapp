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

    val secretHitler = GameTutorial(
        title = "How to play Secret Hitler",
        sections = listOf(
            TutorialSection("Roles", "Liberals are the majority. Fascists are the minority; one of them is Hitler. Fascists know each other and know Hitler. Hitler only learns who the Fascists are in 5–6 player games."),
            TutorialSection("Elect a government", "Each round the President nominates a Chancellor. Everyone votes Ja or Nein. A tie or majority Nein fails the vote and advances the rotation. Three failed votes in a row triggers chaos: the top policy is enacted automatically."),
            TutorialSection("Legislative session", "After a successful vote the President draws 3 policy cards, discards 1, and passes 2 to the Chancellor, who enacts one of them. After five Fascist policies the Chancellor may request a veto — both leaders must agree to discard the pair."),
            TutorialSection("Presidential powers", "Some Fascist policies grant the President a power: peek at the top of the deck, investigate a player's party, call a special election, or execute a player. The board changes with player count."),
            TutorialSection("Winning", "Liberals win by enacting 5 Liberal policies or by executing Hitler. Fascists win by enacting 6 Fascist policies, or by getting Hitler elected Chancellor after 3 Fascist policies are on the board."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Your role", "A coloured card at the top shows your role: Liberal, Fascist, or Hitler. Fascists also see their allies. Keep your phone face-down between turns."),
            TutorialSection("President / Chancellor turns", "When it's your turn to act (nominate, discard, enact, use a power) the buttons appear under the government card. Otherwise the screen tells you who the table is waiting on."),
            TutorialSection("Voting", "When an election opens, tap Ja or Nein. Your vote locks in and the count updates as everyone else votes."),
        ),
    )

    val cheat = GameTutorial(
        title = "How to play Cheat (BS)",
        sections = listOf(
            TutorialSection("Deal", "All 52 cards are dealt face-down to the table. Some hands may be one card bigger — that's fine."),
            TutorialSection("Claim a rank", "On your turn you must play at least one card face-down and claim a rank — Aces first, then 2s, 3s, all the way to Kings, then back to Aces."),
            TutorialSection("Call BS", "Any other player can call BS on the last play. The cards flip — if the claim was a lie the cheater picks up the whole pile. If it was honest, the caller picks it up."),
            TutorialSection("Winning", "Empty your hand and survive the BS window — if no-one calls (or the call fails), you win the round."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Your hand", "Tap cards to lift them out of your hand. The button at the bottom tells you what rank you're claiming and how many cards you'll play."),
            TutorialSection("Calling BS", "When someone else has just played, a red Call BS button appears. Once the next player plays, the window closes — be quick."),
            TutorialSection("Pending win", "When someone plays their last card, the round pauses with Call BS / Accept buttons. Catch the cheater or confirm the win."),
        ),
    )

    val president = GameTutorial(
        title = "How to play President (Scum / Asshole)",
        sections = listOf(
            TutorialSection("Goal", "Shed your hand first to become President. Last out is Scum. The ranks carry into the next round's card-swap."),
            TutorialSection("Tricks", "Each trick the leader plays a combination — single, pair, triple, quad, or run of consecutive pairs. Everyone must match the same type and beat the previous power, or pass. When all but one player passes, that player wins the trick and leads next."),
            TutorialSection("Card order", "Low → high: 3 4 5 6 7 8 9 10 J Q K A 2. Twos are the strongest singles."),
            TutorialSection("Swap phase", "After round 1, Scum gives their 2 best cards to President; President gives back any 2. Vice Scum & Vice President swap 1 each. Good gets better — and worse — fast."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Picking cards", "Tap cards in your hand to highlight them. The Play button shows how many you've picked; tap Pass when you can't (or won't) play."),
            TutorialSection("Swap prompts", "If you owe a swap, a card appears at the top of your screen telling you who gets your cards and whether you choose them or they're picked automatically."),
            TutorialSection("Round end", "When only one player has cards, the round ends and ranks are assigned. The host taps Next round to deal again."),
        ),
    )

    val bluffMarket = GameTutorial(
        title = "How to play Bluff Market",
        sections = listOf(
            TutorialSection("Setup", "Everyone gets 3 face-down cards. Most are positive point cards. Exactly one is the Bomb (-25). You only see your own cards — you don't know who has the Bomb (it may be you)."),
            TutorialSection("Three actions", "On your turn: 1) Propose a trade with another player (both commit a card face-down, both reveal, both decide). 2) Buy the top market card face-down. 3) Sell one of your cards to the market for +2 coins."),
            TutorialSection("The Guarantee", "Once per game each player can invoke The Guarantee, forcing the current trade to complete regardless of how either side answered."),
            TutorialSection("Round end & scoring", "After each player has taken the configured number of turns, hands are revealed. Sum your cards + coins. Subtract 25 if you held the Bomb at scoring."),
        ),
        browserMenuSections = listOf(
            TutorialSection("Your hand", "Tap a card to select it (purple outline). Selling, proposing a trade, and committing a counter-card all use the selected card."),
            TutorialSection("Trade flow", "Proposer offers a card → target commits a counter card (or declines/uses Guarantee). Both cards flip; both accept or reject. If either Guaranteed, the trade is forced."),
            TutorialSection("Scoring", "When the round ends the host taps Reveal to show every hand. The Bomb subtracts 25 from whichever player holds it at that moment."),
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
        "secret_hitler" -> secretHitler
        "cheat" -> cheat
        "president" -> president
        "bluff_market" -> bluffMarket
        "tag" -> tag
        "tic_tac_toe" -> ticTacToe
        "connect_four" -> connectFour
        "real_time" -> realTime
        else -> null
    }
}
