package com.example.jamboree.games.tictactoe

enum class Mark(val symbol: String) {
    EMPTY(""), X("X"), O("O");
    val opponent: Mark get() = when (this) { X -> O; O -> X; EMPTY -> EMPTY }
}

enum class TicTacToeDifficulty {
    EASY, MEDIUM, HARD;

    /** Search depth handed to [TicTacToeAI]. HARD reaches every leaf on a 3x3
     *  (unbeatable); larger boards stay depth-limited so the AI stays snappy. */
    fun searchDepth(boardSize: Int): Int = when (this) {
        EASY -> 1
        MEDIUM -> 3
        HARD -> if (boardSize <= 3) 9 else 5
    }
}

/** Host-configurable knobs. Defaults reproduce the classic 3x3 perfect-AI game. */
data class TicTacToeOptions(
    val boardSize: Int = 3,
    /** 0 = auto: 3 in a row on a 3x3, 4 in a row on larger boards. */
    val winLength: Int = 0,
    val difficulty: TicTacToeDifficulty = TicTacToeDifficulty.HARD,
) {
    companion object {
        val allowedSizes = listOf(3, 4, 5)
        fun autoWinLength(size: Int): Int = if (size <= 3) 3 else 4
    }

    fun normalized(): TicTacToeOptions {
        val size = if (boardSize in allowedSizes) boardSize else 3
        val win = (if (winLength <= 0) autoWinLength(size) else winLength).coerceIn(3, size)
        return copy(boardSize = size, winLength = win)
    }
}

class TicTacToeModel(
    val size: Int = 3,
    val winLength: Int = 3,
) {
    val cellCount: Int get() = size * size
    val board: Array<Mark> = Array(size * size) { Mark.EMPTY }
    var current: Mark = Mark.X

    val winner: Mark? get() {
        for (r in 0 until size) for (c in 0 until size) {
            val m = board[r * size + c]
            if (m == Mark.EMPTY) continue
            for ((dr, dc) in DIRS) {
                var rr = r; var cc = c; var run = 0
                while (rr in 0 until size && cc in 0 until size && board[rr * size + cc] == m) {
                    run++
                    if (run >= winLength) return m
                    rr += dr; cc += dc
                }
            }
        }
        return null
    }
    val isDraw: Boolean get() = winner == null && board.none { it == Mark.EMPTY }
    val isOver: Boolean get() = winner != null || isDraw

    fun reset() { for (i in board.indices) board[i] = Mark.EMPTY; current = Mark.X }

    fun apply(idx: Int) {
        if (idx !in board.indices || board[idx] != Mark.EMPTY || isOver) return
        board[idx] = current
        current = current.opponent
    }

    fun copy(): TicTacToeModel {
        val m = TicTacToeModel(size, winLength)
        for (i in board.indices) m.board[i] = board[i]
        m.current = current
        return m
    }

    companion object {
        val DIRS = arrayOf(intArrayOf(0, 1), intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(1, -1))
    }
}

/**
 * Depth-limited negamax with alpha-beta pruning and a window heuristic at the
 * horizon. Deterministic (no RNG): a depth that reaches every leaf plays
 * perfectly, shallower depths give a beatable opponent.
 */
object TicTacToeAI {
    private const val WIN = 100_000

    fun bestMove(model: TicTacToeModel, ai: Mark, depth: Int): Int? {
        var bestScore = Int.MIN_VALUE / 2
        var bestIdx: Int? = null
        for (i in emptyCells(model)) {
            val copy = model.copy().also { it.apply(i) }
            val s = -negamax(copy, depth - 1, Int.MIN_VALUE / 2, Int.MAX_VALUE / 2)
            if (s > bestScore) { bestScore = s; bestIdx = i }
        }
        return bestIdx
    }

    /** Centre-biased ordering sharpens alpha-beta pruning. */
    private fun emptyCells(m: TicTacToeModel): List<Int> {
        val mid = (m.size - 1) / 2.0
        return (0 until m.cellCount)
            .filter { m.board[it] == Mark.EMPTY }
            .sortedBy {
                val r = it / m.size; val c = it % m.size
                kotlin.math.abs(r - mid) + kotlin.math.abs(c - mid)
            }
    }

    private fun negamax(m: TicTacToeModel, depth: Int, alphaIn: Int, beta: Int): Int {
        if (m.winner != null) return -(WIN - depth)   // previous mover just won → loss for current
        if (m.isDraw) return 0
        if (depth == 0) return heuristic(m, m.current)
        var alpha = alphaIn
        var best = Int.MIN_VALUE / 2
        for (i in emptyCells(m)) {
            val copy = m.copy().also { it.apply(i) }
            val s = -negamax(copy, depth - 1, -beta, -alpha)
            if (s > best) best = s
            if (best > alpha) alpha = best
            if (alpha >= beta) break
        }
        return best
    }

    private fun heuristic(m: TicTacToeModel, ai: Mark): Int {
        val k = m.winLength
        var score = 0
        for (r in 0 until m.size) for (c in 0 until m.size) for ((dr, dc) in TicTacToeModel.DIRS) {
            val endR = r + (k - 1) * dr; val endC = c + (k - 1) * dc
            if (endR !in 0 until m.size || endC !in 0 until m.size) continue
            var mine = 0; var theirs = 0
            for (i in 0 until k) {
                val cell = m.board[(r + i * dr) * m.size + (c + i * dc)]
                if (cell == ai) mine++ else if (cell == ai.opponent) theirs++
            }
            if (mine > 0 && theirs > 0) continue
            if (mine > 0) score += mine * mine else if (theirs > 0) score -= theirs * theirs
        }
        return score
    }
}
