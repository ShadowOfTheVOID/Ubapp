/// Static tutorial content for every game. Each entry is a list of
/// short sections rendered page-by-page by [TutorialView] (or, for
/// browser-tier games, by the matching HTML/JS bundle).
class TutorialSection {
  const TutorialSection({required this.heading, required this.body});
  final String heading;
  final String body;

  Map<String, String> toJson() => {'heading': heading, 'body': body};
}

class GameTutorial {
  const GameTutorial({
    required this.title,
    required this.sections,
    this.browserMenuSections = const [],
  });
  final String title;
  final List<TutorialSection> sections;

  /// Extra sections that explain the *browser-side* UI for browser-tier
  /// games. Shown only to guests; the Flutter host doesn't need them
  /// because it has its own screen.
  final List<TutorialSection> browserMenuSections;

  List<Map<String, String>> sectionsJson() =>
      sections.map((s) => s.toJson()).toList();

  List<Map<String, String>> browserMenuSectionsJson() =>
      browserMenuSections.map((s) => s.toJson()).toList();
}

class GameTutorials {
  static const mafia = GameTutorial(
    title: 'How to play Mafia',
    sections: [
      TutorialSection(
        heading: 'Setup',
        body:
            'Every player gets a secret role: Mafia, Doctor, or Villager. '
            'Mafia know each other; the rest of the town does not.',
      ),
      TutorialSection(
        heading: 'Night',
        body:
            'Mafia secretly pick one player to kill. The Doctor secretly '
            'picks one player to save (and may self-save once per game).',
      ),
      TutorialSection(
        heading: 'Day',
        body:
            'Everyone learns who died. The whole town discusses and votes '
            'to eliminate one suspect. Majority is required to lynch.',
      ),
      TutorialSection(
        heading: 'Winning',
        body:
            'Town wins if all Mafia are eliminated. Mafia win when they '
            'equal or outnumber the remaining town.',
      ),
    ],
    browserMenuSections: [
      TutorialSection(
        heading: 'Your role',
        body:
            'When the game starts a colored card shows your role at the '
            'top of the screen. Keep your phone face-down between turns.',
      ),
      TutorialSection(
        heading: 'Acting at night',
        body:
            'If you have a night ability you will see a target list. Tap '
            'a player to highlight them, then tap Confirm. You can only '
            'submit once per night.',
      ),
      TutorialSection(
        heading: 'Day vote',
        body:
            'Tap the player you want to lynch (or Skip vote), then tap '
            'Lock in vote. The day resolves once everyone has voted.',
      ),
    ],
  );

  static const werewolf = GameTutorial(
    title: 'How to play Werewolf',
    sections: [
      TutorialSection(
        heading: 'Roles',
        body:
            'Werewolves hunt the village at night and know each other. '
            'The Seer privately learns whether one player is a werewolf '
            'each night. The Hunter takes one player down with them when '
            'killed. Everyone else is a Villager.',
      ),
      TutorialSection(
        heading: 'Night',
        body:
            'Werewolves coordinate to pick a victim. The Seer picks a '
            'player to investigate and privately learns their alignment.',
      ),
      TutorialSection(
        heading: 'Day',
        body:
            'Reveal who died, then the village discusses and votes to '
            'lynch a suspect. Majority lynches.',
      ),
      TutorialSection(
        heading: 'Hunter shot',
        body:
            'If a Hunter dies (night or day), the game pauses and they '
            'pick one player to take with them. If that player is also '
            'a Hunter, the chain continues.',
      ),
      TutorialSection(
        heading: 'Winning',
        body:
            'Village wins if all Werewolves are eliminated. Werewolves '
            'win when they equal or outnumber the rest.',
      ),
    ],
    browserMenuSections: [
      TutorialSection(
        heading: 'Your role',
        body:
            'A colored card at the top reveals your role. Werewolves '
            'also see a list of their fellow wolves.',
      ),
      TutorialSection(
        heading: 'Night actions',
        body:
            'Werewolves and the Seer see a target list at night. Tap a '
            'player, then Confirm. The Seer\'s findings are listed in a '
            "Seer findings card visible only to the Seer.",
      ),
      TutorialSection(
        heading: 'Hunter shot',
        body:
            'If you are the Hunter and you die, you will see a "Take one '
            'with you" prompt. Tap a player, then Fire.',
      ),
      TutorialSection(
        heading: 'Day vote',
        body:
            'Tap a suspect (or Skip vote), then Lock in vote. Resolves '
            'when everyone alive has voted.',
      ),
    ],
  );

  static const imposter = GameTutorial(
    title: 'How to play Imposter',
    sections: [
      TutorialSection(
        heading: 'Setup',
        body:
            'One player is secretly the Imposter. Everyone else is a '
            'townie. Townies see a category AND a secret word. The '
            'Imposter sees only the category.',
      ),
      TutorialSection(
        heading: 'Discussion',
        body:
            'Take turns asking each other questions about the word — '
            'vague enough that you do not give it away, specific enough '
            'to prove you actually know it.',
      ),
      TutorialSection(
        heading: 'Vote',
        body:
            'When you are ready, vote on who you think is the Imposter. '
            'The most-voted player is revealed.',
      ),
      TutorialSection(
        heading: 'Winning',
        body:
            'Townies win if they correctly vote out the Imposter. The '
            'Imposter wins if a townie is voted out instead.',
      ),
    ],
    browserMenuSections: [
      TutorialSection(
        heading: 'Your card',
        body:
            'A big card shows your secret word and category — or '
            '"IMPOSTER" and just the category if you are the bluffer. '
            'Memorise it, then hide your phone.',
      ),
      TutorialSection(
        heading: 'Discussion',
        body:
            'There are no on-screen actions while you talk. Ask each '
            'other questions in person. The host will call a vote when '
            'the table is ready.',
      ),
      TutorialSection(
        heading: 'Voting',
        body:
            'A list of every other player appears. Tap one (or Skip), '
            'then Lock in vote. You cannot change your vote after.',
      ),
    ],
  );

  static const codenames = GameTutorial(
    title: 'How to play Codenames',
    sections: [
      TutorialSection(
        heading: 'Setup',
        body:
            'Two teams (red and blue). Each team picks one Spymaster who '
            'sees which words belong to which team, plus an Assassin '
            'word and neutral words.',
      ),
      TutorialSection(
        heading: 'Clues',
        body:
            'On your turn, the Spymaster gives a one-word clue and a '
            'number — e.g. "Animal 3". The clue must relate to that '
            'many of your team\'s words on the board.',
      ),
      TutorialSection(
        heading: 'Guessing',
        body:
            'Operatives discuss and tap words. A correct word stays on '
            'your team. A neutral or enemy word ends your turn. The '
            'Assassin ends the game — your team loses immediately.',
      ),
      TutorialSection(
        heading: 'Winning',
        body:
            'First team to reveal all of their words wins.',
      ),
    ],
    browserMenuSections: [
      TutorialSection(
        heading: 'Joining a team',
        body:
            'In the lobby tap Join Red or Join Blue. Then tap Be '
            'Spymaster if you want to give clues — each team needs '
            'exactly one. The host starts when both teams are ready.',
      ),
      TutorialSection(
        heading: 'Spymaster view',
        body:
            'Spymasters see a coloured outline on every card showing '
            "its allegiance (your colour, the enemy's, neutral, or the "
            'assassin). Do NOT show your phone to your team.',
      ),
      TutorialSection(
        heading: 'Giving a clue',
        body:
            'When it is your turn as Spymaster type a one-word clue and '
            'a number, then send. Operatives discuss out loud and tap '
            'cards to guess; the Spymaster cannot tap.',
      ),
      TutorialSection(
        heading: 'Guessing',
        body:
            'Operatives tap a word card to reveal it. Correct cards '
            "stay your colour. A wrong card ends your turn. Tap End "
            'turn early if you want to stop guessing.',
      ),
    ],
  );

  static const crazyEights = GameTutorial(
    title: 'How to play Crazy Eights',
    sections: [
      TutorialSection(
        heading: 'Deal',
        body:
            'Each player is dealt a hand of cards from a standard 52-card '
            'deck. The top of the deck flips up as the discard pile.',
      ),
      TutorialSection(
        heading: 'Your turn',
        body:
            'Play a card matching the suit or rank on top of the discard. '
            'If you cannot, draw from the deck until you can play.',
      ),
      TutorialSection(
        heading: 'Eights are wild',
        body:
            'You can play an 8 on anything, and you choose the new suit '
            'the next player must follow.',
      ),
      TutorialSection(
        heading: 'Winning',
        body:
            'First player to empty their hand wins the round.',
      ),
    ],
    browserMenuSections: [
      TutorialSection(
        heading: 'Your hand',
        body:
            'Your cards are along the bottom of the screen. Playable '
            'cards are highlighted; unplayable ones look faded.',
      ),
      TutorialSection(
        heading: 'Playing a card',
        body:
            'Tap a card to select it (it turns purple), then tap the '
            'Play button that appears. If you played an 8, a popup asks '
            'you to declare the new active suit.',
      ),
      TutorialSection(
        heading: 'Drawing & passing',
        body:
            'If you cannot play, tap the draw pile on the left of the '
            'table. If the new card is playable you can still play it; '
            'otherwise tap Pass to end your turn.',
      ),
    ],
  );

  static const tag = GameTutorial(
    title: 'How to play Tag (BLE proximity)',
    sections: [
      TutorialSection(
        heading: 'Pair up',
        body:
            'Every phone running the app advertises a BLE beacon and '
            'scans for nearby phones. Stay within a few meters of each '
            'other for the proximity detector to pick you up.',
      ),
      TutorialSection(
        heading: 'It and not-it',
        body:
            'One player is "It" (highlighted red). Get close to a '
            'not-It player to tag them and pass It along.',
      ),
      TutorialSection(
        heading: 'Variants',
        body:
            'Try Freeze Tag (tagged players freeze until rescued), '
            'Infection (tagged players also become It), or Sharks & '
            'Minnows. Pick one in the lobby before starting.',
      ),
      TutorialSection(
        heading: 'Have fun',
        body:
            'No phones-in-pockets cheating. Hold the device where the '
            'antenna can breathe.',
      ),
    ],
  );

  static const ticTacToe = GameTutorial(
    title: 'How to play Tic-Tac-Toe',
    sections: [
      TutorialSection(
        heading: 'Goal',
        body:
            'Get three of your marks in a row — horizontally, '
            'vertically, or diagonally.',
      ),
      TutorialSection(
        heading: 'Turns',
        body:
            'You are X, the AI is O. Tap an empty cell to play. The AI '
            'uses a perfect-play search, so your best result against it '
            'is a draw.',
      ),
    ],
  );

  static const connectFour = GameTutorial(
    title: 'How to play Connect Four',
    sections: [
      TutorialSection(
        heading: 'Goal',
        body:
            'Drop discs into the columns. First to line up four discs '
            'in a row, column, or diagonal wins.',
      ),
      TutorialSection(
        heading: 'Turns',
        body:
            'Tap a column to drop your disc. The AI alternates with '
            'you. The center column tends to be the strongest opener.',
      ),
    ],
  );

  static const realTime = GameTutorial(
    title: 'How to play Real-time',
    sections: [
      TutorialSection(
        heading: 'Movement',
        body:
            'Drag on the screen to move your player around the arena.',
      ),
      TutorialSection(
        heading: 'Enemies',
        body:
            'Four AI enemies wander around. When you get close, they '
            'switch to Chase mode and come after you. Stay just far '
            'enough away to keep them wandering.',
      ),
    ],
  );

  /// Look up a tutorial by stable key (used by browser bundles).
  static GameTutorial? byKey(String key) => switch (key) {
        'mafia' => mafia,
        'werewolf' => werewolf,
        'imposter' => imposter,
        'codenames' => codenames,
        'crazy_eights' => crazyEights,
        'tag' => tag,
        'tic_tac_toe' => ticTacToe,
        'connect_four' => connectFour,
        'real_time' => realTime,
        _ => null,
      };
}
