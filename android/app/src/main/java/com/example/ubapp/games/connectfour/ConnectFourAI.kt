package com.example.ubapp.games.connectfour

/**
 * Depth-limited negamax with alpha-beta pruning + simple line-score heuristic
 * at horizon. Depth 6 plays a reasonable medium-strength opponent.
 */
object ConnectFourAI {
    fun bestMove(model: ConnectFourModel, ai: Disc, depth: Int = 6): Int? {
        var bestScore = Int.MIN_VALUE / 2
        var bestCol: Int? = null
        for (col in ordered(model.legalMoves())) {
            val copy = copyOf(model).apply { apply(col) }
            val s = negamax(copy, ai.opponent, depth - 1,
                            Int.MIN_VALUE / 2, Int.MAX_VALUE / 2, ai)
            if (s > bestScore) { bestScore = s; bestCol = col }
        }
        return bestCol
    }

    private fun copyOf(m: ConnectFourModel): ConnectFourModel {
        val out = ConnectFourModel()
        for (c in 0 until COLS) for (r in 0 until ROWS) out.board[c][r] = m.board[c][r]
        out.current = m.current
        return out
    }

    private fun ordered(moves: List<Int>): List<Int> =
        moves.sortedBy { kotlin.math.abs(it - COLS / 2) }

    private fun negamax(m: ConnectFourModel, toMove: Disc, depth: Int,
                        alphaIn: Int, beta: Int, ai: Disc): Int {
        m.winner?.let { return if (it == ai) 100_000 - depth else -100_000 + depth }
        if (m.isDraw) return 0
        if (depth == 0) return heuristic(m, ai)
        var alpha = alphaIn
        var best = Int.MIN_VALUE / 2
        for (col in ordered(m.legalMoves())) {
            val copy = copyOf(m).apply { apply(col) }
            val s = -negamax(copy, toMove.opponent, depth - 1, -beta, -alpha, ai)
            if (s > best) best = s
            if (best > alpha) alpha = best
            if (alpha >= beta) break
        }
        return if (toMove == ai) best else -best
    }

    private fun heuristic(m: ConnectFourModel, ai: Disc): Int {
        var score = 0
        val dirs = listOf(1 to 0, 0 to 1, 1 to 1, 1 to -1)
        for (c in 0 until COLS) for (r in 0 until ROWS) for ((dc, dr) in dirs) {
            if (!inBounds(c + 3 * dc, r + 3 * dr)) continue
            score += scoreWindow(m, c, r, dc, dr, ai)
        }
        // Center column control matters.
        for (r in 0 until ROWS) {
            if (m.at(COLS / 2, r) == ai) score += 3
            if (m.at(COLS / 2, r) == ai.opponent) score -= 3
        }
        return score
    }

    private fun inBounds(c: Int, r: Int) = c in 0 until COLS && r in 0 until ROWS

    private fun scoreWindow(m: ConnectFourModel, c: Int, r: Int,
                            dc: Int, dr: Int, ai: Disc): Int {
        var mine = 0; var theirs = 0; var empty = 0
        for (i in 0 until 4) {
            val d = m.at(c + i * dc, r + i * dr)
            when (d) {
                ai -> mine++
                ai.opponent -> theirs++
                else -> empty++
            }
        }
        if (mine > 0 && theirs > 0) return 0
        if (mine == 4) return 100
        if (mine == 3 && empty == 1) return 10
        if (mine == 2 && empty == 2) return 2
        if (theirs == 3 && empty == 1) return -12
        if (theirs == 2 && empty == 2) return -2
        return 0
    }
}
