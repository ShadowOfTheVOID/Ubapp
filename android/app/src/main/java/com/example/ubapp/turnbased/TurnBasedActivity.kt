package com.example.ubapp.turnbased

import android.os.Bundle
import android.view.Gravity
import android.widget.GridLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.example.ubapp.R
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.lifecycle.lifecycleScope

class TurnBasedActivity : AppCompatActivity() {

    private val model = TicTacToeModel()
    private val cells = arrayOfNulls<MaterialButton>(9)
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_turn_based)

        status = findViewById(R.id.status)
        val grid = findViewById<GridLayout>(R.id.board)
        buildBoard(grid)

        findViewById<MaterialButton>(R.id.btnNewGame).setOnClickListener {
            model.reset()
            refresh()
        }
        refresh()
    }

    private fun buildBoard(grid: GridLayout) {
        grid.columnCount = 3
        grid.rowCount = 3
        grid.post {
            grid.removeAllViews()
            val cellSize = grid.width / 3
            for (i in 0..8) {
                val button = MaterialButton(this).apply {
                    text = ""
                    textSize = 36f
                    cornerRadius = 16
                    gravity = Gravity.CENTER
                }
                val params = GridLayout.LayoutParams().apply {
                    width = cellSize - 16
                    height = cellSize - 16
                    setMargins(8, 8, 8, 8)
                    rowSpec = GridLayout.spec(i / 3)
                    columnSpec = GridLayout.spec(i % 3)
                }
                button.layoutParams = params
                button.setOnClickListener { onCellTapped(i) }
                grid.addView(button)
                cells[i] = button
            }
            refresh()
        }
    }

    private fun onCellTapped(index: Int) {
        if (model.isOver || model.markAt(index) != Mark.EMPTY || model.current != Mark.X) return
        model.apply(index)
        refresh()
        if (model.isOver) return
        status.text = getString(R.string.status_ai_thinking)
        lifecycleScope.launch {
            val move = withContext(Dispatchers.Default) { Minimax.bestMove(model, Mark.O) }
            move?.let { model.apply(it) }
            refresh()
        }
    }

    private fun refresh() {
        for (i in 0..8) cells[i]?.text = model.markAt(i).symbol
        status.text = when {
            model.winner == Mark.X -> getString(R.string.status_you_win)
            model.winner == Mark.O -> getString(R.string.status_ai_wins)
            model.isDraw -> getString(R.string.status_draw)
            model.current == Mark.X -> getString(R.string.status_your_turn)
            else -> getString(R.string.status_ai_thinking)
        }
    }
}
