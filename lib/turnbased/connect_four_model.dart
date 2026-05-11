enum Disc { empty, red, yellow }

extension DiscX on Disc {
  Disc get opponent => switch (this) {
        Disc.red => Disc.yellow,
        Disc.yellow => Disc.red,
        Disc.empty => Disc.empty,
      };
  String get symbol => switch (this) {
        Disc.empty => '',
        Disc.red => 'R',
        Disc.yellow => 'Y',
      };
}

const int kCols = 7;
const int kRows = 6;

class ConnectFourModel {
  /// Column-major: board[col][row], row 0 = bottom.
  final List<List<Disc>> board =
      List.generate(kCols, (_) => List<Disc>.filled(kRows, Disc.empty));
  Disc current = Disc.red;

  Disc at(int col, int row) => board[col][row];

  bool isLegal(int col) =>
      col >= 0 && col < kCols && board[col][kRows - 1] == Disc.empty;

  Iterable<int> legalMoves() sync* {
    for (var c = 0; c < kCols; c++) {
      if (isLegal(c)) yield c;
    }
  }

  /// Apply a move. Returns the row the disc landed on, or -1 if illegal.
  int apply(int col) {
    if (!isLegal(col) || isOver) return -1;
    for (var r = 0; r < kRows; r++) {
      if (board[col][r] == Disc.empty) {
        board[col][r] = current;
        current = current.opponent;
        return r;
      }
    }
    return -1;
  }

  Disc? get winner {
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        final d = board[c][r];
        if (d == Disc.empty) continue;
        for (final dir in const [
          [1, 0], [0, 1], [1, 1], [1, -1],
        ]) {
          if (_runOf(c, r, dir[0], dir[1], d) >= 4) return d;
        }
      }
    }
    return null;
  }

  int _runOf(int c, int r, int dc, int dr, Disc d) {
    var count = 0;
    while (c >= 0 && c < kCols && r >= 0 && r < kRows && board[c][r] == d) {
      count++;
      c += dc;
      r += dr;
    }
    return count;
  }

  bool get isDraw =>
      winner == null && List.generate(kCols, isLegal).every((b) => !b);

  bool get isOver => winner != null || isDraw;

  void reset() {
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        board[c][r] = Disc.empty;
      }
    }
    current = Disc.red;
  }

  ConnectFourModel copy() {
    final m = ConnectFourModel();
    for (var c = 0; c < kCols; c++) {
      for (var r = 0; r < kRows; r++) {
        m.board[c][r] = board[c][r];
      }
    }
    m.current = current;
    return m;
  }
}
