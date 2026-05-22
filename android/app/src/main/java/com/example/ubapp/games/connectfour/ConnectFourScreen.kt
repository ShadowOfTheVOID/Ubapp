package com.example.ubapp.games.connectfour

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.stats.StatsStore
import com.example.ubapp.stats.SeriesScore
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.tutorials.GameTutorials
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val boardPresets = listOf(6 to 5, 7 to 6, 8 to 7)

@Composable
fun ConnectFourScreen() {
    var options by remember { mutableStateOf(ConnectFourOptions().normalized()) }
    var model by remember(options) {
        mutableStateOf(ConnectFourModel(options.cols, options.rows, options.connectN))
    }
    var thinking by remember { mutableStateOf(false) }
    var showTutorial by remember { mutableStateOf(false) }
    // Running tally across rematches in this sitting; resets when options change.
    val series = remember(options) { SeriesScore() }
    var seriesText by remember(options) { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current

    LaunchedEffect(model) {
        if (model.isOver) {
            val outcome = when (model.winner) {
                Disc.RED -> "red"
                Disc.YELLOW -> "yellow"
                else -> "draw"
            }
            StatsStore.record(ctx.applicationContext, "connect_four", listOf("You", "CPU"), outcome)
            series.record(when (model.winner) { Disc.RED -> "You"; Disc.YELLOW -> "CPU"; else -> "Draw" })
            seriesText = series.banner()
        }
    }

    fun mutate(block: ConnectFourModel.() -> Unit) {
        model = model.copy().apply(block)
    }

    val status = model.winner?.let { (if (it == Disc.RED) "Red" else "Yellow") + " wins" }
        ?: if (model.isDraw) "Draw" else (if (model.current == Disc.RED) "Red" else "Yellow") + " to play"
    val disc = when { options.cols <= 6 -> 44; options.cols == 7 -> 38; else -> 32 }.dp

    UbappTheme {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Column(
        Modifier.widthIn(max = 520.dp).fillMaxWidth().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(status, style = MaterialTheme.typography.titleLarge)
        if (seriesText.isNotEmpty()) {
            Text(seriesText, style = MaterialTheme.typography.bodyMedium)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((c, r) in boardPresets) {
                FilterChip(
                    selected = options.cols == c && options.rows == r,
                    onClick = { if (!thinking) options = options.copy(cols = c, rows = r).normalized() },
                    label = { Text("${c}x$r") },
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (d in ConnectFourDifficulty.entries) {
                FilterChip(
                    selected = options.difficulty == d,
                    onClick = { if (!thinking) options = options.copy(difficulty = d) },
                    label = { Text(d.name.lowercase().replaceFirstChar { it.uppercase() }) },
                )
            }
        }

        Column(
            Modifier.background(Color(0xFF1976D2).copy(alpha = 0.2f), RoundedCornerShape(12.dp)).padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            for (r in (options.rows - 1) downTo 0) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (c in 0 until options.cols) {
                        val d = model.board[c][r]
                        val color = when (d) {
                            Disc.RED -> Color.Red
                            Disc.YELLOW -> Color(0xFFFFD54F)
                            Disc.EMPTY -> Color.Gray.copy(alpha = 0.3f)
                        }
                        Box(
                            Modifier.size(disc).clip(CircleShape).background(color)
                                .clickable(enabled = !thinking && !model.isOver && model.isLegal(c) && model.current == Disc.RED) {
                                    mutate { apply(c) }
                                    if (!model.isOver) {
                                        thinking = true
                                        scope.launch {
                                            val depth = options.difficulty.searchDepth()
                                            val ai = withContext(Dispatchers.Default) {
                                                ConnectFourAI.bestMove(model.copy(), Disc.YELLOW, depth)
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

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = { model = ConnectFourModel(options.cols, options.rows, options.connectN) }, enabled = !thinking) {
                Text("Reset")
            }
            TextButton(onClick = { showTutorial = true }) { Text("How to play") }
        }
    }
    }

    if (showTutorial) {
        val tut = GameTutorials.connectFour
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
