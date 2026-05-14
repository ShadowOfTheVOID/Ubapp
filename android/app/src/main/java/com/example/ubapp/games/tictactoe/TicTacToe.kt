package com.example.ubapp.games.tictactoe

enum class Mark(val symbol: String) {
    EMPTY(""), X("X"), O("O");
    val opponent: Mark get() = when (this) { X -> O; O -> X; EMPTY -> EMPTY }
}

private val winningLines = listOf(
    intArrayOf(0,1,2), intArrayOf(3,4,5), intArrayOf(6,7,8),
    intArrayOf(0,3,6), intArrayOf(1,4,7), intArrayOf(2,5,8),
    intArrayOf(0,4,8), intArrayOf(2,4,6),
)

class TicTacToeModel {
    val board: Array<Mark> = Array(9) { Mark.EMPTY }
    var current: Mark = Mark.X

    val winner: Mark? get() {
        for (line in winningLines) {
            val a = board[line[0]]
            if (a != Mark.EMPTY && a == board[line[1]] && a == board[line[2]]) return a
        }
        return null
    }
    val isDraw: Boolean get() = winner == null && board.none { it == Mark.EMPTY }
    val isOver: Boolean get() = winner != null || isDraw

    fun reset() { for (i in 0..8) board[i] = Mark.EMPTY; current = Mark.X }

    fun apply(idx: Int) {
        if (board[idx] != Mark.EMPTY || isOver) return
        board[idx] = current
        current = current.opponent
    }

    fun copy(): TicTacToeModel {
        val m = TicTacToeModel()
        for (i in 0..8) m.board[i] = board[i]
        m.current = current
        return m
    }
}

object Minimax {
    fun bestMove(model: TicTacToeModel, ai: Mark): Int? {
        var best = Int.MIN_VALUE; var bestIdx: Int? = null
        for (i in 0..8) {
            if (model.board[i] != Mark.EMPTY) continue
            val copy = model.copy().also { it.apply(i) }
            val s = score(copy, ai, false, 0)
            if (s > best) { best = s; bestIdx = i }
        }
        return bestIdx
    }
    private fun score(m: TicTacToeModel, ai: Mark, maximizing: Boolean, depth: Int): Int {
        val w = m.winner
        if (w != null) return if (w == ai) 100 - depth else depth - 100
        if (m.isDraw) return 0
        var best = if (maximizing) Int.MIN_VALUE else Int.MAX_VALUE
        for (i in 0..8) {
            if (m.board[i] != Mark.EMPTY) continue
            val copy = m.copy().also { it.apply(i) }
            val s = score(copy, ai, !maximizing, depth + 1)
            best = if (maximizing) maxOf(s, best) else minOf(s, best)
        }
        return best
    }
}
