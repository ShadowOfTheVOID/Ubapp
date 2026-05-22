import Foundation

/// Depth-limited negamax with alpha-beta pruning + simple line-score heuristic
/// at the horizon. Reads the board geometry and win length straight off the
/// model, so it adapts to non-default board sizes. Depth 5 (medium) plays a
/// reasonable opponent on the classic 7x6 board.
enum ConnectFourAI {
    static func bestMove(_ model: ConnectFourModel, ai: Disc, depth: Int = 6) -> Int? {
        var bestScore = Int.min / 2
        var bestCol: Int?
        for col in ordered(model, model.legalMoves()) {
            var copy = model
            copy.apply(col)
            // After the AI moves it's the opponent's turn; negamax returns the
            // value from the opponent's perspective, so the AI wants the move
            // that minimizes it (= maximizes its negation).
            let s = -negamax(copy, toMove: ai.opponent, depth: depth - 1,
                             alpha: Int.min / 2, beta: Int.max / 2)
            if s > bestScore { bestScore = s; bestCol = col }
        }
        return bestCol
    }

    private static func ordered(_ m: ConnectFourModel, _ moves: [Int]) -> [Int] {
        moves.sorted { abs($0 - m.cols / 2) < abs($1 - m.cols / 2) }
    }

    /// Standard negamax: returns the score from `toMove`'s perspective.
    private static func negamax(_ m: ConnectFourModel, toMove: Disc, depth: Int,
                                 alpha alphaIn: Int, beta: Int) -> Int {
        // A decided board at a node where `toMove` is on the move means the
        // opponent just made the winning move — a loss for `toMove`.
        if m.winner != nil { return -(100_000 - depth) }
        if m.isDraw { return 0 }
        if depth == 0 { return heuristic(m, ai: toMove) }
        var alpha = alphaIn
        var best = Int.min / 2
        for col in ordered(m, m.legalMoves()) {
            var copy = m
            copy.apply(col)
            let s = -negamax(copy, toMove: toMove.opponent, depth: depth - 1,
                             alpha: -beta, beta: -alpha)
            if s > best { best = s }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return best
    }

    private static func heuristic(_ m: ConnectFourModel, ai: Disc) -> Int {
        let k = m.connectN
        var score = 0
        let dirs = [(1, 0), (0, 1), (1, 1), (1, -1)]
        for c in 0..<m.cols {
            for r in 0..<m.rows {
                for (dc, dr) in dirs {
                    if !inBounds(m, c + (k - 1) * dc, r + (k - 1) * dr) { continue }
                    score += scoreWindow(m, c: c, r: r, dc: dc, dr: dr, ai: ai)
                }
            }
        }
        // Center column control matters.
        for r in 0..<m.rows {
            if m.at(m.cols / 2, r) == ai { score += 3 }
            if m.at(m.cols / 2, r) == ai.opponent { score -= 3 }
        }
        return score
    }

    private static func inBounds(_ m: ConnectFourModel, _ c: Int, _ r: Int) -> Bool {
        c >= 0 && c < m.cols && r >= 0 && r < m.rows
    }

    private static func scoreWindow(_ m: ConnectFourModel, c: Int, r: Int,
                                     dc: Int, dr: Int, ai: Disc) -> Int {
        let k = m.connectN
        var mine = 0, theirs = 0, empty = 0
        for i in 0..<k {
            let d = m.at(c + i * dc, r + i * dr)
            if d == ai { mine += 1 }
            else if d == ai.opponent { theirs += 1 }
            else { empty += 1 }
        }
        if mine > 0 && theirs > 0 { return 0 }
        if mine == k { return 100 }
        if mine == k - 1 && empty == 1 { return 10 }
        if mine == k - 2 && empty == 2 { return 2 }
        if theirs == k - 1 && empty == 1 { return -12 }
        if theirs == k - 2 && empty == 2 { return -2 }
        return 0
    }
}
