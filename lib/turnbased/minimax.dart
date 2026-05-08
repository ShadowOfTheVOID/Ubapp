import 'tic_tac_toe_model.dart';

int? bestMove(TicTacToeModel model, Mark ai) {
  var bestScore = -1 << 30;
  int? bestIdx;
  for (var i = 0; i < 9; i++) {
    if (model.board[i] != Mark.empty) continue;
    final copy = model.copy();
    copy.apply(i);
    final s = _score(copy, ai, false, 0);
    if (s > bestScore) {
      bestScore = s;
      bestIdx = i;
    }
  }
  return bestIdx;
}

int _score(TicTacToeModel m, Mark ai, bool maximizing, int depth) {
  final w = m.winner;
  if (w != null) return w == ai ? 100 - depth : depth - 100;
  if (m.isDraw) return 0;

  var best = maximizing ? -1 << 30 : 1 << 30;
  for (var i = 0; i < 9; i++) {
    if (m.board[i] != Mark.empty) continue;
    final copy = m.copy();
    copy.apply(i);
    final s = _score(copy, ai, !maximizing, depth + 1);
    best = maximizing ? (s > best ? s : best) : (s < best ? s : best);
  }
  return best;
}
