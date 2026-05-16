package com.example.ubapp.games.imposter

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

@Composable
fun ImposterScreen() {
    val ctx = LocalContext.current
    val server = remember { ImposterServer(ctx) }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    var selectedCategory by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HostingChrome(joinUrl) { joinUrl = server.start() }
        Text("Phase: ${e.phase}", style = MaterialTheme.typography.titleMedium)

        when (e.phase) {
            ImposterPhase.LOBBY -> {
                TutorialVoteCard(
                    state = e.tutorialVote.snapshot(), tutorial = GameTutorials.imposter,
                    onCall = server::hostCallTutorialVote, onVote = server::hostTutorialVote,
                    onDismiss = server::hostDismissTutorial,
                )
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Players (${e.players.size})", style = MaterialTheme.typography.titleSmall)
                        for (p in e.players.values.sortedBy { it.id }) {
                            Text(p.name + if (p.isHost) " (host)" else "")
                        }
                    }
                }
                Text("Category", style = MaterialTheme.typography.titleSmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = selectedCategory == null,
                               onClick = { selectedCategory = null }, label = { Text("Random") },
                               enabled = !e.options.mixedPool)
                    for (c in e.availableCategories.sorted()) {
                        FilterChip(selected = selectedCategory == c,
                                   onClick = { selectedCategory = c }, label = { Text(c) },
                                   enabled = !e.options.mixedPool)
                    }
                }
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Options", style = MaterialTheme.typography.titleSmall)
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text("Imposters: ${e.options.imposterCount}", Modifier.weight(1f))
                            IconButton(onClick = {
                                server.hostSetOptions(
                                    e.options.copy(imposterCount = (e.options.imposterCount - 1).coerceAtLeast(1))
                                )
                            }, enabled = e.options.imposterCount > 1) {
                                Text("−", style = MaterialTheme.typography.titleLarge)
                            }
                            IconButton(onClick = {
                                server.hostSetOptions(
                                    e.options.copy(
                                        imposterCount = (e.options.imposterCount + 1).coerceAtMost(e.maxImposterCount)
                                    )
                                )
                            }, enabled = e.options.imposterCount < e.maxImposterCount) {
                                Text("+", style = MaterialTheme.typography.titleLarge)
                            }
                        }
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Switch(checked = e.options.decoyWord,
                                   onCheckedChange = { server.hostSetOptions(e.options.copy(decoyWord = it)) })
                            Text("  Decoy word for imposters")
                        }
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Switch(checked = e.options.hideCategory,
                                   onCheckedChange = { server.hostSetOptions(e.options.copy(hideCategory = it)) })
                            Text("  Hide category from imposters")
                        }
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Switch(checked = e.options.mixedPool,
                                   onCheckedChange = { server.hostSetOptions(e.options.copy(mixedPool = it)) })
                            Text("  Mixed-category pool")
                        }
                    }
                }
                Button(onClick = { server.hostStart(if (e.options.mixedPool) null else selectedCategory) },
                       enabled = e.canStart) {
                    Text(if (e.canStart) "Start round" else "Need 3+ players")
                }
            }
            ImposterPhase.PLAYING -> {
                ElevatedCard {
                    Column(Modifier.padding(16.dp)) {
                        val host = e.players[ImposterServer.HOST_ID]
                        val hostIsImposter = host?.isImposter == true
                        if (!(hostIsImposter && e.options.hideCategory)) {
                            Text("Category: ${e.category}", style = MaterialTheme.typography.titleMedium)
                        }
                        if (hostIsImposter) {
                            Text("IMPOSTER",
                                 style = MaterialTheme.typography.displaySmall,
                                 color = Color.Red, fontWeight = FontWeight.Bold)
                            val decoy = host?.decoyWord
                            if (decoy != null) {
                                Text("Decoy word: $decoy",
                                     style = MaterialTheme.typography.titleMedium,
                                     fontWeight = FontWeight.Bold)
                                Text("This isn't the real word — bluff carefully.",
                                     style = MaterialTheme.typography.bodySmall)
                            } else {
                                Text("Bluff your way through.")
                            }
                        } else {
                            Text(e.secretWord,
                                 style = MaterialTheme.typography.displaySmall,
                                 fontWeight = FontWeight.Bold)
                        }
                    }
                }
                Button(onClick = { server.hostBeginVoting() }) { Text("Call vote") }
            }
            ImposterPhase.VOTING -> {
                Text("Vote: who is the imposter?", style = MaterialTheme.typography.titleSmall)
                for (p in e.players.values.filter { it.id != ImposterServer.HOST_ID }) {
                    OutlinedButton(onClick = { server.hostVote(p.id) },
                                   modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
                OutlinedButton(onClick = { server.hostVote(null) },
                               modifier = Modifier.fillMaxWidth()) { Text("Skip vote") }
            }
            ImposterPhase.RESULT, ImposterPhase.GAME_OVER -> {
                Text(if (e.winner == ImposterWinner.TOWN) "Town wins" else "Imposter wins",
                     style = MaterialTheme.typography.headlineSmall)
                val names = e.imposterIds.mapNotNull { e.players[it]?.name }.sorted()
                if (names.isNotEmpty()) {
                    val label = if (names.size == 1) "imposter was" else "imposters were"
                    Text("The $label ${names.joinToString(", ")}.")
                }
                Text("Word: ${e.secretWord}  ·  Category: ${e.category}",
                     style = MaterialTheme.typography.bodySmall)
                Button(onClick = { server.hostNewRound() }) { Text("New round") }
            }
        }
    }
}
