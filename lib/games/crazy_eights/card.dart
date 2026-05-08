enum Suit { clubs, diamonds, hearts, spades }

extension SuitX on Suit {
  String get short => switch (this) {
        Suit.clubs => 'C',
        Suit.diamonds => 'D',
        Suit.hearts => 'H',
        Suit.spades => 'S',
      };
  String get glyph => switch (this) {
        Suit.clubs => '♣',
        Suit.diamonds => '♦',
        Suit.hearts => '♥',
        Suit.spades => '♠',
      };
  bool get isRed => this == Suit.diamonds || this == Suit.hearts;
}

class Card {
  const Card(this.suit, this.rank);
  final Suit suit;
  final int rank; // 2..14 (J=11, Q=12, K=13, A=14)

  String get rankShort => switch (rank) {
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        14 => 'A',
        _ => '$rank',
      };

  String get id => '${suit.short}$rank';

  Map<String, Object?> toJson() => {'suit': suit.name, 'rank': rank};

  static Card fromJson(Map<String, Object?> j) =>
      Card(Suit.values.byName(j['suit']! as String), j['rank']! as int);

  @override
  bool operator ==(Object other) =>
      other is Card && other.suit == suit && other.rank == rank;
  @override
  int get hashCode => Object.hash(suit, rank);
  @override
  String toString() => '$rankShort${suit.glyph}';
}

List<Card> standardDeck() => [
      for (final s in Suit.values)
        for (var r = 2; r <= 14; r++) Card(s, r),
    ];
