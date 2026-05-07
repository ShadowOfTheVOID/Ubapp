package com.example.ubapp.turnbased

enum class Mark(val symbol: String) {
    EMPTY(""), X("X"), O("O");

    val opponent: Mark
        get() = when (this) {
            X -> O
            O -> X
            EMPTY -> EMPTY
        }
}

class TicTacToeModel {
    val board: IntArray = IntArray(9)
    var current: Mark = Mark.X

    val winner: Mark?
        get() {
            for (line in WINNING_LINES) {
                val a = board[line[0]]
                if (a != 0 && a == board[line[1]] && a == board[line[2]]) {
                    return if (a == 1) Mark.X else Mark.O
                }
            }
            return null
        }

    val isDraw: Boolean
        get() = winner == null && board.none { it == 0 }

    val isOver: Boolean
        get() = winner != null || isDraw

    fun reset() {
        board.fill(0)
        current = Mark.X
    }

    fun apply(index: Int) {
        if (board[index] != 0 || isOver) return
        board[index] = if (current == Mark.X) 1 else 2
        current = current.opponent
    }

    fun copy(): TicTacToeModel {
        val m = TicTacToeModel()
        System.arraycopy(board, 0, m.board, 0, 9)
        m.current = current
        return m
    }

    fun markAt(index: Int): Mark = when (board[index]) {
        1 -> Mark.X
        2 -> Mark.O
        else -> Mark.EMPTY
    }

    companion object {
        private val WINNING_LINES = arrayOf(
            intArrayOf(0, 1, 2), intArrayOf(3, 4, 5), intArrayOf(6, 7, 8),
            intArrayOf(0, 3, 6), intArrayOf(1, 4, 7), intArrayOf(2, 5, 8),
            intArrayOf(0, 4, 8), intArrayOf(2, 4, 6)
        )
    }
}
