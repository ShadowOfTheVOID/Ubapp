package com.example.ubapp.games.connectfour

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ConnectFourScreen() {
    var model by remember { mutableStateOf(ConnectFourModel()) }
    var thinking by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun snapshot(): ConnectFourModel {
        val m = ConnectFourModel()
        for (c in 0 until COLS) for (r in 0 until ROWS) m.board[c][r] = model.board[c][r]
        m.current = model.current
        return m
    }

    fun mutate(block: ConnectFourModel.() -> Unit) {
        val m = snapshot().apply(block)
        model = m
    }

    val status = model.winner?.let { (if (it == Disc.RED) "Red" else "Yellow") + " wins" }
        ?: if (model.isDraw) "Draw" else (if (model.current == Disc.RED) "Red" else "Yellow") + " to play"

    Column(
        Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(status, style = MaterialTheme.typography.titleLarge)
        Column(
            Modifier.background(Color(0xFF1976D2).copy(alpha = 0.2f), RoundedCornerShape(12.dp)).padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            for (r in (ROWS - 1) downTo 0) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (c in 0 until COLS) {
                        val d = model.board[c][r]
                        val color = when (d) {
                            Disc.RED -> Color.Red
                            Disc.YELLOW -> Color(0xFFFFD54F)
                            Disc.EMPTY -> Color.Gray.copy(alpha = 0.3f)
                        }
                        Box(
                            Modifier.size(40.dp).clip(CircleShape).background(color)
                                .clickable(enabled = !thinking && !model.isOver && model.isLegal(c) && model.current == Disc.RED) {
                                    mutate { apply(c) }
                                    if (!model.isOver) {
                                        thinking = true
                                        scope.launch {
                                            val ai = withContext(Dispatchers.Default) {
                                                ConnectFourAI.bestMove(snapshot(), Disc.YELLOW, 5)
                                            }
                                            if (ai != null) mutate { apply(ai) }
                                            thinking = false
                                        }
                                    }
                                }
                        )
                    }
                }
            }
        }
        Button(onClick = { model = ConnectFourModel() }, enabled = !thinking) { Text("Reset") }
    }
}
