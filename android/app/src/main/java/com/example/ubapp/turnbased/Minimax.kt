package com.example.ubapp.turnbased

import kotlin.math.max
import kotlin.math.min

object Minimax {
    fun bestMove(model: TicTacToeModel, ai: Mark): Int? {
        var bestScore = Int.MIN_VALUE
        var bestIdx: Int? = null
        for (i in 0..8) {
            if (model.board[i] != 0) continue
            val copy = model.copy()
            copy.apply(i)
            val score = score(copy, ai, false, 0)
            if (score > bestScore) {
                bestScore = score
                bestIdx = i
            }
        }
        return bestIdx
    }

    private fun score(model: TicTacToeModel, ai: Mark, maximizing: Boolean, depth: Int): Int {
        model.winner?.let { return if (it == ai) 100 - depth else depth - 100 }
        if (model.isDraw) return 0

        var best = if (maximizing) Int.MIN_VALUE else Int.MAX_VALUE
        for (i in 0..8) {
            if (model.board[i] != 0) continue
            val copy = model.copy()
            copy.apply(i)
            val s = score(copy, ai, !maximizing, depth + 1)
            best = if (maximizing) max(best, s) else min(best, s)
        }
        return best
    }
}
