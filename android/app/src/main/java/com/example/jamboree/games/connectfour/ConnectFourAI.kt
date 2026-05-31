package com.example.jamboree.games.connectfour

/**
 * Depth-limited negamax with alpha-beta pruning + simple line-score heuristic
 * at the horizon. Reads the board geometry and win length straight off the
 * model, so it adapts to non-default board sizes. Depth 5 (MEDIUM) plays a
 * reasonable opponent on the classic 7x6 board.
 */
object ConnectFourAI {
    fun bestMove(model: ConnectFourModel, ai: Disc, depth: Int = 6): Int? {
        var bestScore = Int.MIN_VALUE / 2
        var bestCol: Int? = null
        for (col in ordered(model, model.legalMoves())) {
            val copy = model.copy().apply { apply(col) }
            // After the AI moves it's the opponent's turn; negamax returns the
            // value from the opponent's perspective, so the AI wants the move
            // that minimizes it (= maximizes its negation).
            val s = -negamax(copy, ai.opponent, depth - 1,
                             Int.MIN_VALUE / 2, Int.MAX_VALUE / 2)
            if (s > bestScore) { bestScore = s; bestCol = col }
        }
        return bestCol
    }

    private fun ordered(m: ConnectFourModel, moves: List<Int>): List<Int> =
        moves.sortedBy { kotlin.math.abs(it - m.cols / 2) }

    /** Standard negamax: returns the score from [toMove]'s perspective. */
    private fun negamax(m: ConnectFourModel, toMove: Disc, depth: Int,
                        alphaIn: Int, beta: Int): Int {
        // A decided board at a node where [toMove] is on the move means the
        // opponent just made the winning move — a loss for [toMove].
        if (m.winner != null) return -(100_000 - depth)
        if (m.isDraw) return 0
        if (depth == 0) return heuristic(m, toMove)
        var alpha = alphaIn
        var best = Int.MIN_VALUE / 2
        for (col in ordered(m, m.legalMoves())) {
            val copy = m.copy().apply { apply(col) }
            val s = -negamax(copy, toMove.opponent, depth - 1, -beta, -alpha)
            if (s > best) best = s
            if (best > alpha) alpha = best
            if (alpha >= beta) break
        }
        return best
    }

    private fun heuristic(m: ConnectFourModel, ai: Disc): Int {
        val k = m.connectN
        var score = 0
        for (c in 0 until m.cols) for (r in 0 until m.rows) for ((dc, dr) in ConnectFourModel.DIRS) {
            if (!inBounds(m, c + (k - 1) * dc, r + (k - 1) * dr)) continue
            score += scoreWindow(m, c, r, dc, dr, ai)
        }
        // Center column control matters.
        for (r in 0 until m.rows) {
            if (m.at(m.cols / 2, r) == ai) score += 3
            if (m.at(m.cols / 2, r) == ai.opponent) score -= 3
        }
        return score
    }

    private fun inBounds(m: ConnectFourModel, c: Int, r: Int) =
        c in 0 until m.cols && r in 0 until m.rows

    private fun scoreWindow(m: ConnectFourModel, c: Int, r: Int,
                            dc: Int, dr: Int, ai: Disc): Int {
        val k = m.connectN
        var mine = 0; var theirs = 0; var empty = 0
        for (i in 0 until k) {
            val d = m.at(c + i * dc, r + i * dr)
            when (d) {
                ai -> mine++
                ai.opponent -> theirs++
                else -> empty++
            }
        }
        if (mine > 0 && theirs > 0) return 0
        if (mine == k) return 100
        if (mine == k - 1 && empty == 1) return 10
        if (mine == k - 2 && empty == 2) return 2
        if (theirs == k - 1 && empty == 1) return -12
        if (theirs == k - 2 && empty == 2) return -2
        return 0
    }
}
