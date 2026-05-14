import Foundation

/// Depth-limited negamax with alpha-beta pruning + simple line-score
/// heuristic at horizon. Depth 6 plays a reasonable medium-strength opponent.
enum ConnectFourAI {
    static func bestMove(_ model: ConnectFourModel, ai: Disc, depth: Int = 6) -> Int? {
        var bestScore = Int.min
        var bestCol: Int?
        for col in ordered(model.legalMoves()) {
            var copy = model
            copy.apply(col)
            let s = negamax(copy, toMove: ai.opponent, depth: depth - 1,
                            alpha: Int.min / 2, beta: Int.max / 2, ai: ai)
            if s > bestScore { bestScore = s; bestCol = col }
        }
        return bestCol
    }

    private static func ordered(_ moves: [Int]) -> [Int] {
        moves.sorted { abs($0 - kCols / 2) < abs($1 - kCols / 2) }
    }

    private static func negamax(_ m: ConnectFourModel, toMove: Disc, depth: Int,
                                 alpha alphaIn: Int, beta: Int, ai: Disc) -> Int {
        if let w = m.winner { return w == ai ? 100_000 - depth : -100_000 + depth }
        if m.isDraw { return 0 }
        if depth == 0 { return heuristic(m, ai: ai) }
        var alpha = alphaIn
        var best = Int.min / 2
        for col in ordered(m.legalMoves()) {
            var copy = m
            copy.apply(col)
            let s = -negamax(copy, toMove: toMove.opponent, depth: depth - 1,
                             alpha: -beta, beta: -alpha, ai: ai)
            if s > best { best = s }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return toMove == ai ? best : -best
    }

    /// Score every length-4 window: heavy positive if the AI has a near-complete
    /// line with no opponent disc, heavy negative if the opponent does.
    private static func heuristic(_ m: ConnectFourModel, ai: Disc) -> Int {
        var score = 0
        let dirs = [(1,0),(0,1),(1,1),(1,-1)]
        for c in 0..<kCols {
            for r in 0..<kRows {
                for (dc, dr) in dirs {
                    if !inBounds(c + 3*dc, r + 3*dr) { continue }
                    score += scoreWindow(m, c: c, r: r, dc: dc, dr: dr, ai: ai)
                }
            }
        }
        // Center column control matters.
        for r in 0..<kRows {
            if m.at(kCols / 2, r) == ai { score += 3 }
            if m.at(kCols / 2, r) == ai.opponent { score -= 3 }
        }
        return score
    }

    private static func inBounds(_ c: Int, _ r: Int) -> Bool {
        c >= 0 && c < kCols && r >= 0 && r < kRows
    }

    private static func scoreWindow(_ m: ConnectFourModel, c: Int, r: Int,
                                     dc: Int, dr: Int, ai: Disc) -> Int {
        var mine = 0, theirs = 0, empty = 0
        for i in 0..<4 {
            let d = m.at(c + i * dc, r + i * dr)
            if d == ai { mine += 1 }
            else if d == ai.opponent { theirs += 1 }
            else { empty += 1 }
        }
        if mine > 0 && theirs > 0 { return 0 }
        if mine == 4 { return 100 }
        if mine == 3 && empty == 1 { return 10 }
        if mine == 2 && empty == 2 { return 2 }
        if theirs == 3 && empty == 1 { return -12 }
        if theirs == 2 && empty == 2 { return -2 }
        return 0
    }
}
