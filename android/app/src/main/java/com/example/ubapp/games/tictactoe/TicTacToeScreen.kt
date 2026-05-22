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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.stats.StatsStore
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.tutorials.GameTutorials
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun TicTacToeScreen() {
    var options by remember { mutableStateOf(TicTacToeOptions().normalized()) }
    var model by remember(options) { mutableStateOf(TicTacToeModel(options.boardSize, options.winLength)) }
    var thinking by remember { mutableStateOf(false) }
    var showTutorial by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current

    LaunchedEffect(model) {
        if (model.isOver) {
            val outcome = when (model.winner) {
                Mark.X -> "x"
                Mark.O -> "o"
                else -> "draw"
            }
            StatsStore.record(ctx.applicationContext, "tic_tac_toe", listOf("You", "CPU"), outcome)
        }
    }

    fun mutate(block: TicTacToeModel.() -> Unit) {
        model = model.copy().apply(block)
    }

    val status = model.winner?.let { "${it.symbol} wins" }
        ?: if (model.isDraw) "Draw" else "${model.current.symbol} to play"
    val cell = when (options.boardSize) { 3 -> 80; 4 -> 60; else -> 48 }.dp
    val mark = when (options.boardSize) { 3 -> 48; 4 -> 34; else -> 26 }.sp

    UbappTheme {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Column(
        Modifier.widthIn(max = 480.dp).fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(status, style = MaterialTheme.typography.titleLarge)

        // Board size + difficulty selectors. Changing either resets the board.
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (s in TicTacToeOptions.allowedSizes) {
                FilterChip(
                    selected = options.boardSize == s,
                    onClick = { if (!thinking) options = options.copy(boardSize = s).normalized() },
                    label = { Text("${s}x$s") },
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (d in TicTacToeDifficulty.entries) {
                FilterChip(
                    selected = options.difficulty == d,
                    onClick = { if (!thinking) options = options.copy(difficulty = d) },
                    label = { Text(d.name.lowercase().replaceFirstChar { it.uppercase() }) },
                )
            }
        }

        for (row in 0 until options.boardSize) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (col in 0 until options.boardSize) {
                    val idx = row * options.boardSize + col
                    val disabled = model.board[idx] != Mark.EMPTY || model.isOver || thinking
                    Box(
                        Modifier.size(cell)
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .clickable(enabled = !disabled) {
                                if (model.current != Mark.X) return@clickable
                                mutate { apply(idx) }
                                if (!model.isOver) {
                                    thinking = true
                                    scope.launch {
                                        val depth = options.difficulty.searchDepth(model.size)
                                        val ai = withContext(Dispatchers.Default) {
                                            TicTacToeAI.bestMove(model.copy(), Mark.O, depth)
                                        }
                                        if (ai != null) mutate { apply(ai) }
                                        thinking = false
                                    }
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(model.board[idx].symbol, fontSize = mark, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = { model = TicTacToeModel(options.boardSize, options.winLength) }, enabled = !thinking) {
                Text("Reset")
            }
            TextButton(onClick = { showTutorial = true }) { Text("How to play") }
        }
    }
    }

    if (showTutorial) {
        val tut = GameTutorials.ticTacToe
        AlertDialog(
            onDismissRequest = { showTutorial = false },
            confirmButton = { TextButton(onClick = { showTutorial = false }) { Text("Got it") } },
            title = { Text(tut.title) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (s in tut.sections) {
                        Text(s.heading, style = MaterialTheme.typography.titleSmall)
                        Text(s.body, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            },
        )
    }
    }
}
