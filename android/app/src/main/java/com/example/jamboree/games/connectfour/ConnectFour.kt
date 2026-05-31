package com.example.jamboree.games.connectfour

enum class Disc(val symbol: String) {
    EMPTY(""), RED("R"), YELLOW("Y");
    val opponent: Disc get() = when (this) { RED -> YELLOW; YELLOW -> RED; EMPTY -> EMPTY }
}

enum class ConnectFourDifficulty {
    EASY, MEDIUM, HARD;
    /** Negamax search depth handed to [ConnectFourAI]. */
    fun searchDepth(): Int = when (this) { EASY -> 2; MEDIUM -> 5; HARD -> 7 }
}

/** Host-configurable knobs. Defaults reproduce the classic 7x6 connect-4 game. */
data class ConnectFourOptions(
    val cols: Int = 7,
    val rows: Int = 6,
    val connectN: Int = 4,
    val difficulty: ConnectFourDifficulty = ConnectFourDifficulty.MEDIUM,
) {
    fun normalized(): ConnectFourOptions {
        val c = cols.coerceIn(5, 10)
        val r = rows.coerceIn(4, 10)
        return copy(cols = c, rows = r, connectN = connectN.coerceIn(3, minOf(c, r)))
    }
}

class ConnectFourModel(
    val cols: Int = 7,
    val rows: Int = 6,
    val connectN: Int = 4,
) {
    /** Column-major: board[col][row], row 0 = bottom. */
    val board: Array<Array<Disc>> = Array(cols) { Array(rows) { Disc.EMPTY } }
    var current: Disc = Disc.RED

    fun at(col: Int, row: Int) = board[col][row]
    fun isLegal(col: Int) = col in 0 until cols && board[col][rows - 1] == Disc.EMPTY
    fun legalMoves(): List<Int> = (0 until cols).filter { isLegal(it) }

    /** Returns the row the disc landed on, or -1 if illegal. */
    fun apply(col: Int): Int {
        if (!isLegal(col) || isOver) return -1
        for (r in 0 until rows) if (board[col][r] == Disc.EMPTY) {
            board[col][r] = current
            current = current.opponent
            return r
        }
        return -1
    }

    val winner: Disc? get() {
        for (c in 0 until cols) for (r in 0 until rows) {
            val d = board[c][r]
            if (d == Disc.EMPTY) continue
            for ((dc, dr) in DIRS)
                if (runOf(c, r, dc, dr, d) >= connectN) return d
        }
        return null
    }
    private fun runOf(cStart: Int, rStart: Int, dc: Int, dr: Int, d: Disc): Int {
        var c = cStart; var r = rStart; var count = 0
        while (c in 0 until cols && r in 0 until rows && board[c][r] == d) {
            count++; c += dc; r += dr
        }
        return count
    }
    val isDraw: Boolean get() = winner == null && (0 until cols).none { isLegal(it) }
    val isOver: Boolean get() = winner != null || isDraw

    fun reset() {
        for (c in 0 until cols) for (r in 0 until rows) board[c][r] = Disc.EMPTY
        current = Disc.RED
    }

    fun copy(): ConnectFourModel {
        val out = ConnectFourModel(cols, rows, connectN)
        for (c in 0 until cols) for (r in 0 until rows) out.board[c][r] = board[c][r]
        out.current = current
        return out
    }

    companion object {
        val DIRS = listOf(1 to 0, 0 to 1, 1 to 1, 1 to -1)
    }
}
