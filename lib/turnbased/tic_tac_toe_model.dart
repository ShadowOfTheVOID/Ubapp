enum Mark { empty, x, o }

extension MarkX on Mark {
  String get symbol => switch (this) {
        Mark.empty => '',
        Mark.x => 'X',
        Mark.o => 'O',
      };

  Mark get opponent => switch (this) {
        Mark.x => Mark.o,
        Mark.o => Mark.x,
        Mark.empty => Mark.empty,
      };
}

const _winningLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [0, 3, 6], [1, 4, 7], [2, 5, 8],
  [0, 4, 8], [2, 4, 6],
];

class TicTacToeModel {
  final List<Mark> board = List<Mark>.filled(9, Mark.empty);
  Mark current = Mark.x;

  Mark? get winner {
    for (final line in _winningLines) {
      final a = board[line[0]];
      if (a != Mark.empty && a == board[line[1]] && a == board[line[2]]) {
        return a;
      }
    }
    return null;
  }

  bool get isDraw => winner == null && !board.contains(Mark.empty);
  bool get isOver => winner != null || isDraw;

  void reset() {
    for (var i = 0; i < 9; i++) {
      board[i] = Mark.empty;
    }
    current = Mark.x;
  }

  void apply(int index) {
    if (board[index] != Mark.empty || isOver) return;
    board[index] = current;
    current = current.opponent;
  }

  TicTacToeModel copy() {
    final m = TicTacToeModel();
    for (var i = 0; i < 9; i++) {
      m.board[i] = board[i];
    }
    m.current = current;
    return m;
  }
}
