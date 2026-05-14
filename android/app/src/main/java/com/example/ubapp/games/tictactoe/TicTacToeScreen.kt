package com.example.ubapp.games.tictactoe

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun TicTacToeScreen() {
    var model by remember { mutableStateOf(TicTacToeModel()) }
    var thinking by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun snapshot() = model.copy().also { it.current = model.current }
    fun mutate(block: TicTacToeModel.() -> Unit) {
        val m = TicTacToeModel().apply {
            for (i in 0..8) board[i] = model.board[i]; current = model.current
            block()
        }
        model = m
    }

    val status = model.winner?.let { "${it.symbol} wins" }
        ?: if (model.isDraw) "Draw" else "${model.current.symbol} to play"

    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(status, style = MaterialTheme.typography.titleLarge)
        for (row in 0..2) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (col in 0..2) {
                    val idx = row * 3 + col
                    val disabled = model.board[idx] != Mark.EMPTY || model.isOver || thinking
                    Box(
                        Modifier.size(80.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .clickable(enabled = !disabled) {
                                if (model.current != Mark.X) return@clickable
                                mutate { apply(idx) }
                                if (!model.isOver) {
                                    thinking = true
                                    scope.launch {
                                        val ai = withContext(Dispatchers.Default) {
                                            Minimax.bestMove(model.copy(), Mark.O)
                                        }
                                        if (ai != null) mutate { apply(ai) }
                                        thinking = false
                                    }
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(model.board[idx].symbol, fontSize = 48.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        Button(onClick = { model = TicTacToeModel() }) { Text("Reset") }
    }
}
