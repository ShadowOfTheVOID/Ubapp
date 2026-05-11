import 'connect_four_model.dart';

/// Depth-limited minimax with alpha-beta pruning + simple line-score
/// heuristic at horizon. Connect Four state space is too big for full search;
/// depth 6 plays a reasonable medium-strength opponent.
int? bestMove(ConnectFourModel model, Disc ai, {int depth = 6}) {
  int bestScore = -1 << 30;
  int? bestCol;
  // Center-first ordering — strongest move historically.
  final order = _ordered(model.legalMoves().toList());
  for (final col in order) {
    final copy = model.copy();
    copy.apply(col);
    final s = _negamax(copy, ai.opponent, depth - 1, -1 << 30, 1 << 30, ai);
    if (s > bestScore) {
      bestScore = s;
      bestCol = col;
    }
  }
  return bestCol;
}

List<int> _ordered(List<int> moves) {
  moves.sort((a, b) =>
      (a - kCols ~/ 2).abs().compareTo((b - kCols ~/ 2).abs()));
  return moves;
}

int _negamax(ConnectFourModel m, Disc toMove, int depth, int alpha, int beta, Disc ai) {
  final w = m.winner;
  if (w != null) return w == ai ? 100000 - depth : -100000 + depth;
  if (m.isDraw) return 0;
  if (depth == 0) return _heuristic(m, ai);

  var best = -1 << 30;
  for (final col in _ordered(m.legalMoves().toList())) {
    final copy = m.copy();
    copy.apply(col);
    final s = -_negamax(copy, toMove.opponent, depth - 1, -beta, -alpha, ai);
    if (s > best) best = s;
    if (best > alpha) alpha = best;
    if (alpha >= beta) break;
  }
  return toMove == ai ? best : -best;
}

/// Score every length-4 window: +heavy if the AI has a near-complete line
/// with no opponent disc, -heavy if the opponent does.
int _heuristic(ConnectFourModel m, Disc ai) {
  int score = 0;
  for (var c = 0; c < kCols; c++) {
    for (var r = 0; r < kRows; r++) {
      for (final dir in const [
        [1, 0], [0, 1], [1, 1], [1, -1],
      ]) {
        if (!_inBounds(c + 3 * dir[0], r + 3 * dir[1])) continue;
        score += _scoreWindow(m, c, r, dir[0], dir[1], ai);
      }
    }
  }
  // Center column control matters.
  for (var r = 0; r < kRows; r++) {
    if (m.at(kCols ~/ 2, r) == ai) score += 3;
    if (m.at(kCols ~/ 2, r) == ai.opponent) score -= 3;
  }
  return score;
}

bool _inBounds(int c, int r) => c >= 0 && c < kCols && r >= 0 && r < kRows;

int _scoreWindow(ConnectFourModel m, int c, int r, int dc, int dr, Disc ai) {
  var mine = 0, theirs = 0, empty = 0;
  for (var i = 0; i < 4; i++) {
    final d = m.at(c + i * dc, r + i * dr);
    if (d == ai) {
      mine++;
    } else if (d == ai.opponent) {
      theirs++;
    } else {
      empty++;
    }
  }
  if (mine > 0 && theirs > 0) return 0;
  if (mine == 4) return 100;
  if (mine == 3 && empty == 1) return 10;
  if (mine == 2 && empty == 2) return 2;
  if (theirs == 3 && empty == 1) return -12;
  if (theirs == 2 && empty == 2) return -2;
  return 0;
}
