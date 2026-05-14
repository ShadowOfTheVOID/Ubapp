package com.example.ubapp.games.connectfour

enum class Disc(val symbol: String) {
    EMPTY(""), RED("R"), YELLOW("Y");
    val opponent: Disc get() = when (this) { RED -> YELLOW; YELLOW -> RED; EMPTY -> EMPTY }
}

const val COLS = 7
const val ROWS = 6

class ConnectFourModel {
    /** Column-major: board[col][row], row 0 = bottom. */
    val board: Array<Array<Disc>> = Array(COLS) { Array(ROWS) { Disc.EMPTY } }
    var current: Disc = Disc.RED

    fun at(col: Int, row: Int) = board[col][row]
    fun isLegal(col: Int) = col in 0 until COLS && board[col][ROWS - 1] == Disc.EMPTY
    fun legalMoves(): List<Int> = (0 until COLS).filter { isLegal(it) }

    /** Returns the row the disc landed on, or -1 if illegal. */
    fun apply(col: Int): Int {
        if (!isLegal(col) || isOver) return -1
        for (r in 0 until ROWS) if (board[col][r] == Disc.EMPTY) {
            board[col][r] = current
            current = current.opponent
            return r
        }
        return -1
    }

    val winner: Disc? get() {
        for (c in 0 until COLS) for (r in 0 until ROWS) {
            val d = board[c][r]
            if (d == Disc.EMPTY) continue
            for ((dc, dr) in listOf(1 to 0, 0 to 1, 1 to 1, 1 to -1))
                if (runOf(c, r, dc, dr, d) >= 4) return d
        }
        return null
    }
    private fun runOf(cStart: Int, rStart: Int, dc: Int, dr: Int, d: Disc): Int {
        var c = cStart; var r = rStart; var count = 0
        while (c in 0 until COLS && r in 0 until ROWS && board[c][r] == d) {
            count++; c += dc; r += dr
        }
        return count
    }
    val isDraw: Boolean get() = winner == null && (0 until COLS).none { isLegal(it) }
    val isOver: Boolean get() = winner != null || isDraw

    fun reset() {
        for (c in 0 until COLS) for (r in 0 until ROWS) board[c][r] = Disc.EMPTY
        current = Disc.RED
    }
}
