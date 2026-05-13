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
  const GameTutorial({required this.title, required this.sections});
  final String title;
  final List<TutorialSection> sections;

  List<Map<String, String>> sectionsJson() =>
      sections.map((s) => s.toJson()).toList();
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
