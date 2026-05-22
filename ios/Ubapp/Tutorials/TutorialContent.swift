import Foundation

/// One short page in a tutorial.
struct TutorialSection {
    let heading: String
    let body: String

    func toJSON() -> [String: String] { ["heading": heading, "body": body] }
}

/// One game's tutorial: title + ordered sections, plus optional
/// browser-side menu sections shown only to web guests.
struct GameTutorial {
    let title: String
    let sections: [TutorialSection]
    let browserMenuSections: [TutorialSection]

    init(title: String, sections: [TutorialSection], browserMenuSections: [TutorialSection] = []) {
        self.title = title; self.sections = sections; self.browserMenuSections = browserMenuSections
    }

    func sectionsJSON() -> [[String: String]] { sections.map { $0.toJSON() } }
    func browserMenuSectionsJSON() -> [[String: String]] { browserMenuSections.map { $0.toJSON() } }
}

/// Static tutorial content for every game. Mirrors lib/tutorials/tutorial_content.dart.
enum GameTutorials {
    static let mafia = GameTutorial(
        title: "How to play Mafia",
        sections: [
            TutorialSection(heading: "Setup", body: "Every player gets a secret role: Mafia, Doctor, or Villager. Mafia know each other; the rest of the town does not."),
            TutorialSection(heading: "Night", body: "Mafia secretly pick one player to kill. The Doctor secretly picks one player to save (and may self-save once per game)."),
            TutorialSection(heading: "Day", body: "Everyone learns who died. The whole town discusses and votes to eliminate one suspect. Majority is required to lynch."),
            TutorialSection(heading: "Winning", body: "Town wins if all Mafia are eliminated. Mafia win when they equal or outnumber the remaining town."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Your role", body: "When the game starts a colored card shows your role at the top of the screen. Keep your phone face-down between turns."),
            TutorialSection(heading: "Acting at night", body: "If you have a night ability you will see a target list. Tap a player to highlight them, then tap Confirm. You can only submit once per night."),
            TutorialSection(heading: "Day vote", body: "Tap the player you want to lynch (or Skip vote), then tap Lock in vote. The day resolves once everyone has voted."),
        ]
    )

    static let werewolf = GameTutorial(
        title: "How to play Werewolf",
        sections: [
            TutorialSection(heading: "Roles", body: "Werewolves hunt the village at night and know each other. The Seer privately learns whether one player is a werewolf each night. The Hunter takes one player down with them when killed. Everyone else is a Villager."),
            TutorialSection(heading: "Night", body: "Werewolves coordinate to pick a victim. The Seer picks a player to investigate and privately learns their alignment."),
            TutorialSection(heading: "Day", body: "Reveal who died, then the village discusses and votes to lynch a suspect. Majority lynches."),
            TutorialSection(heading: "Hunter shot", body: "If a Hunter dies (night or day), the game pauses and they pick one player to take with them. If that player is also a Hunter, the chain continues."),
            TutorialSection(heading: "Winning", body: "Village wins if all Werewolves are eliminated. Werewolves win when they equal or outnumber the rest."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Your role", body: "A colored card at the top reveals your role. Werewolves also see a list of their fellow wolves."),
            TutorialSection(heading: "Night actions", body: "Werewolves and the Seer see a target list at night. Tap a player, then Confirm. The Seer's findings are listed in a Seer findings card visible only to the Seer."),
            TutorialSection(heading: "Hunter shot", body: "If you are the Hunter and you die, you will see a \"Take one with you\" prompt. Tap a player, then Fire."),
            TutorialSection(heading: "Day vote", body: "Tap a suspect (or Skip vote), then Lock in vote. Resolves when everyone alive has voted."),
        ]
    )

    static let imposter = GameTutorial(
        title: "How to play Imposter",
        sections: [
            TutorialSection(heading: "Setup", body: "One player is secretly the Imposter. Everyone else is a townie. Townies see a category AND a secret word. The Imposter sees only the category."),
            TutorialSection(heading: "Discussion", body: "Take turns asking each other questions about the word — vague enough that you do not give it away, specific enough to prove you actually know it."),
            TutorialSection(heading: "Vote", body: "When you are ready, vote on who you think is the Imposter. The most-voted player is revealed."),
            TutorialSection(heading: "Winning", body: "Townies win if they correctly vote out the Imposter. The Imposter wins if a townie is voted out instead."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Your card", body: "A big card shows your secret word and category — or \"IMPOSTER\" and just the category if you are the bluffer. Memorise it, then hide your phone."),
            TutorialSection(heading: "Discussion", body: "There are no on-screen actions while you talk. Ask each other questions in person. The host will call a vote when the table is ready."),
            TutorialSection(heading: "Voting", body: "A list of every other player appears. Tap one (or Skip), then Lock in vote. You cannot change your vote after."),
        ]
    )

    static let codenames = GameTutorial(
        title: "How to play Codenames",
        sections: [
            TutorialSection(heading: "Setup", body: "Two teams (red and blue). Each team picks one Spymaster who sees which words belong to which team, plus an Assassin word and neutral words."),
            TutorialSection(heading: "Clues", body: "On your turn, the Spymaster gives a one-word clue and a number — e.g. \"Animal 3\". The clue must relate to that many of your team's words on the board."),
            TutorialSection(heading: "Guessing", body: "Operatives discuss and tap words. A correct word stays on your team. A neutral or enemy word ends your turn. The Assassin ends the game — your team loses immediately."),
            TutorialSection(heading: "Winning", body: "First team to reveal all of their words wins."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Joining a team", body: "In the lobby tap Join Red or Join Blue. Then tap Be Spymaster if you want to give clues — each team needs exactly one. The host starts when both teams are ready."),
            TutorialSection(heading: "Spymaster view", body: "Spymasters see a coloured outline on every card showing its allegiance (your colour, the enemy's, neutral, or the assassin). Do NOT show your phone to your team."),
            TutorialSection(heading: "Giving a clue", body: "When it is your turn as Spymaster type a one-word clue and a number, then send. Operatives discuss out loud and tap cards to guess; the Spymaster cannot tap."),
            TutorialSection(heading: "Guessing", body: "Operatives tap a word card to reveal it. Correct cards stay your colour. A wrong card ends your turn. Tap End turn early if you want to stop guessing."),
        ]
    )

    static let crazyEights = GameTutorial(
        title: "How to play Crazy Eights",
        sections: [
            TutorialSection(heading: "Deal", body: "Each player is dealt a hand of cards from a standard 52-card deck. The top of the deck flips up as the discard pile."),
            TutorialSection(heading: "Your turn", body: "Play a card matching the suit or rank on top of the discard. If you cannot, draw from the deck until you can play."),
            TutorialSection(heading: "Eights are wild", body: "You can play an 8 on anything, and you choose the new suit the next player must follow."),
            TutorialSection(heading: "Winning", body: "First player to empty their hand wins the round."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Your hand", body: "Your cards are along the bottom of the screen. Playable cards are highlighted; unplayable ones look faded."),
            TutorialSection(heading: "Playing a card", body: "Tap a card to select it (it turns purple), then tap the Play button that appears. If you played an 8, a popup asks you to declare the new active suit."),
            TutorialSection(heading: "Drawing & passing", body: "If you cannot play, tap the draw pile on the left of the table. If the new card is playable you can still play it; otherwise tap Pass to end your turn."),
        ]
    )

    static let secretHitler = GameTutorial(
        title: "How to play Secret Hitler",
        sections: [
            TutorialSection(heading: "Roles", body: "Liberals are the majority. Fascists are the minority; one of them is Hitler. Fascists know each other and know Hitler. Hitler only learns who the Fascists are in 5–6 player games."),
            TutorialSection(heading: "Elect a government", body: "Each round the President nominates a Chancellor. Everyone votes Ja or Nein. A tie or majority Nein fails the vote and advances the rotation. Three failed votes in a row triggers chaos: the top policy is enacted automatically."),
            TutorialSection(heading: "Legislative session", body: "After a successful vote the President draws 3 policy cards, discards 1, and passes 2 to the Chancellor, who enacts one of them. After five Fascist policies the Chancellor may request a veto — both leaders must agree to discard the pair."),
            TutorialSection(heading: "Presidential powers", body: "Some Fascist policies grant the President a power: peek at the top of the deck, investigate a player's party, call a special election, or execute a player. The board changes with player count."),
            TutorialSection(heading: "Winning", body: "Liberals win by enacting 5 Liberal policies or by executing Hitler. Fascists win by enacting 6 Fascist policies, or by getting Hitler elected Chancellor after 3 Fascist policies are on the board."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Your role", body: "A coloured card at the top shows your role: Liberal, Fascist, or Hitler. Fascists also see their allies. Keep your phone face-down between turns."),
            TutorialSection(heading: "President / Chancellor turns", body: "When it's your turn to act (nominate, discard, enact, use a power) the buttons appear under the government card. Otherwise the screen tells you who the table is waiting on."),
            TutorialSection(heading: "Voting", body: "When an election opens, tap Ja or Nein. Your vote locks in and the count updates as everyone else votes."),
        ]
    )

    static let cheat = GameTutorial(
        title: "How to play Cheat (BS)",
        sections: [
            TutorialSection(heading: "Deal", body: "All 52 cards are dealt face-down to the table. Some hands may be one card bigger — that's fine."),
            TutorialSection(heading: "Claim a rank", body: "On your turn you must play at least one card face-down and claim a rank — Aces first, then 2s, 3s, all the way to Kings, then back to Aces."),
            TutorialSection(heading: "Call BS", body: "Any other player can call BS on the last play. The cards flip — if the claim was a lie the cheater picks up the whole pile. If it was honest, the caller picks it up."),
            TutorialSection(heading: "Winning", body: "Empty your hand and survive the BS window — if no-one calls (or the call fails), you win the round."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Your hand", body: "Tap cards to lift them out of your hand. The button at the bottom tells you what rank you're claiming and how many cards you'll play."),
            TutorialSection(heading: "Calling BS", body: "When someone else has just played, a red Call BS button appears. Once the next player plays, the window closes — be quick."),
            TutorialSection(heading: "Pending win", body: "When someone plays their last card, the round pauses with Call BS / Accept buttons. Catch the cheater or confirm the win."),
        ]
    )

    static let president = GameTutorial(
        title: "How to play President (Scum / Asshole)",
        sections: [
            TutorialSection(heading: "Goal", body: "Shed your hand first to become President. Last out is Scum. The ranks carry into the next round's card-swap."),
            TutorialSection(heading: "Tricks", body: "Each trick the leader plays a combination — single, pair, triple, quad, or run of consecutive pairs. Everyone must match the same type and beat the previous power, or pass. When all but one player passes, that player wins the trick and leads next."),
            TutorialSection(heading: "Card order", body: "Low → high: 3 4 5 6 7 8 9 10 J Q K A 2. Twos are the strongest singles."),
            TutorialSection(heading: "Swap phase", body: "After round 1, Scum gives their 2 best cards to President; President gives back any 2. Vice Scum & Vice President swap 1 each. Good gets better — and worse — fast."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Picking cards", body: "Tap cards in your hand to highlight them. The Play button shows how many you've picked; tap Pass when you can't (or won't) play."),
            TutorialSection(heading: "Swap prompts", body: "If you owe a swap, a card appears at the top of your screen telling you who gets your cards and whether you choose them or they're picked automatically."),
            TutorialSection(heading: "Round end", body: "When only one player has cards, the round ends and ranks are assigned. The host taps Next round to deal again."),
        ]
    )

    static let bluffMarket = GameTutorial(
        title: "How to play Bluff Market",
        sections: [
            TutorialSection(heading: "Setup", body: "Everyone gets 3 face-down cards. Most are positive point cards. Exactly one is the Bomb (-25). You only see your own cards — you don't know who has the Bomb (it may be you)."),
            TutorialSection(heading: "Three actions", body: "On your turn: 1) Propose a trade with another player (both commit a card face-down, both reveal, both decide). 2) Buy the top market card face-down. 3) Sell one of your cards to the market for +2 coins."),
            TutorialSection(heading: "The Guarantee", body: "Once per game each player can invoke The Guarantee, forcing the current trade to complete regardless of how either side answered."),
            TutorialSection(heading: "Round end & scoring", body: "After each player has taken the configured number of turns, hands are revealed. Sum your cards + coins. Subtract 25 if you held the Bomb at scoring."),
        ],
        browserMenuSections: [
            TutorialSection(heading: "Your hand", body: "Tap a card to select it (purple outline). Selling, proposing a trade, and committing a counter-card all use the selected card."),
            TutorialSection(heading: "Trade flow", body: "Proposer offers a card → target commits a counter card (or declines/uses Guarantee). Both cards flip; both accept or reject. If either Guaranteed, the trade is forced."),
            TutorialSection(heading: "Scoring", body: "When the round ends the host taps Reveal to show every hand. The Bomb subtracts 25 from whichever player holds it at that moment."),
        ]
    )

    static let tag = GameTutorial(
        title: "How to play Tag (BLE proximity)",
        sections: [
            TutorialSection(heading: "Pair up", body: "Every phone running the app advertises a BLE beacon and scans for nearby phones. Stay within a few meters of each other for the proximity detector to pick you up."),
            TutorialSection(heading: "It and not-it", body: "One player is \"It\" (highlighted red). Get close to a not-It player to tag them and pass It along."),
            TutorialSection(heading: "Variants", body: "Try Freeze Tag (tagged players freeze until rescued), Infection (tagged players also become It), or Sharks & Minnows. Pick one in the lobby before starting."),
            TutorialSection(heading: "Have fun", body: "No phones-in-pockets cheating. Hold the device where the antenna can breathe."),
        ]
    )

    static let ticTacToe = GameTutorial(
        title: "How to play Tic-Tac-Toe",
        sections: [
            TutorialSection(heading: "Goal", body: "Line up your marks in a row — horizontally, vertically, or diagonally. On the 3x3 board that means three; on the bigger boards it's four in a row."),
            TutorialSection(heading: "Turns", body: "You are X, the AI is O. Tap an empty cell to play."),
            TutorialSection(heading: "Options", body: "Pick the board size (3x3, 4x4, 5x5) and the AI difficulty before you start. On Hard 3x3 the AI plays perfectly, so the best you can do is a draw."),
        ]
    )

    static let connectFour = GameTutorial(
        title: "How to play Connect Four",
        sections: [
            TutorialSection(heading: "Goal", body: "Drop discs into the columns. First to line up the target number of discs in a row, column, or diagonal wins."),
            TutorialSection(heading: "Turns", body: "Tap a column to drop your disc. The AI alternates with you. The center column tends to be the strongest opener."),
            TutorialSection(heading: "Options", body: "Choose a board size and AI difficulty before you start. Easy looks a couple of moves ahead; Hard searches much deeper."),
        ]
    )

    static let realTime = GameTutorial(
        title: "How to play Real-time",
        sections: [
            TutorialSection(heading: "Movement", body: "Drag on the screen to move your player around the arena."),
            TutorialSection(heading: "Enemies", body: "Four AI enemies wander around. When you get close, they switch to Chase mode and come after you. Stay just far enough away to keep them wandering."),
        ]
    )

    static func byKey(_ key: String) -> GameTutorial? {
        switch key {
        case "mafia": return mafia
        case "werewolf": return werewolf
        case "imposter": return imposter
        case "codenames": return codenames
        case "crazy_eights": return crazyEights
        case "secret_hitler": return secretHitler
        case "cheat": return cheat
        case "president": return president
        case "bluff_market": return bluffMarket
        case "tag": return tag
        case "tic_tac_toe": return ticTacToe
        case "connect_four": return connectFour
        case "real_time": return realTime
        default: return nil
        }
    }
}
