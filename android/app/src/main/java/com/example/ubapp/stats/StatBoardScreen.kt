package com.example.ubapp.stats

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme
import java.text.DateFormat
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatBoardScreen(onBack: () -> Unit) {
    val ctx = LocalContext.current
    var data by remember { mutableStateOf(StatsStore.snapshot(ctx)) }
    var showClearConfirm by remember { mutableStateOf(false) }

    val isEmpty = data.games.isEmpty() && data.recent.isEmpty()
    val sortedGames = data.games.entries.sortedByDescending { it.value.playCount }

    UbappTheme {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Stat board") },
                    navigationIcon = { TextButton(onClick = onBack) { Text("‹ Back") } },
                    actions = {
                        TextButton(
                            onClick = { showClearConfirm = true },
                            enabled = !isEmpty,
                        ) { Text("Clear") }
                    },
                )
            },
        ) { pad ->
            Column(
                Modifier
                    .padding(pad)
                    .padding(horizontal = 20.dp, vertical = 16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                if (isEmpty) {
                    Text(
                        "No games recorded yet.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    )
                } else {
                    if (sortedGames.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text("By game", style = MaterialTheme.typography.titleMedium,
                                 fontWeight = FontWeight.Bold)
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (e in sortedGames) GameCard(e.key, e.value)
                            }
                        }
                    }
                    if (data.recent.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text("Recent games", style = MaterialTheme.typography.titleMedium,
                                 fontWeight = FontWeight.Bold)
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (entry in data.recent) RecentRow(entry)
                            }
                        }
                    }
                }
            }
        }
    }

    if (showClearConfirm) {
        AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            title = { Text("Clear all stats?") },
            text = {
                Text(
                    "This permanently removes play counts and recent games on this device.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    StatsStore.clear(ctx)
                    data = StatsStore.snapshot(ctx)
                    showClearConfirm = false
                }) { Text("Clear") }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirm = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun GameCard(id: String, stat: GameStat) {
    val accent = MaterialTheme.colorScheme.primary
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f)),
        colors = CardDefaults.outlinedCardColors(containerColor = Color.White.copy(alpha = 0.04f)),
    ) {
        Column(Modifier.fillMaxWidth().padding(12.dp),
               verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(StatsStore.gameName(id), Modifier.weight(1f),
                     style = MaterialTheme.typography.titleMedium)
                Text("${stat.playCount} played", color = accent,
                     style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            }
            for ((key, count) in stat.outcomes.entries.sortedByDescending { it.value }) {
                Row(Modifier.fillMaxWidth()) {
                    Text(StatsStore.outcomeLabel(key), Modifier.weight(1f),
                         style = MaterialTheme.typography.bodySmall,
                         color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                    Text("$count", style = MaterialTheme.typography.bodySmall,
                         color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                }
            }
        }
    }
}

@Composable
private fun RecentRow(e: RecentEntry) {
    val accent = MaterialTheme.colorScheme.primary
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f)),
        colors = CardDefaults.outlinedCardColors(containerColor = Color.White.copy(alpha = 0.04f)),
    ) {
        Column(Modifier.fillMaxWidth().padding(12.dp),
               verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(StatsStore.gameName(e.gameId), Modifier.weight(1f),
                     style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(
                    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
                        .format(Date(e.timestamp)),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }
            Text(StatsStore.outcomeLabel(e.outcome), color = accent,
                 style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
            if (e.players.isNotEmpty()) {
                Text(e.players.joinToString(", "),
                     style = MaterialTheme.typography.labelSmall,
                     color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
    }
}
