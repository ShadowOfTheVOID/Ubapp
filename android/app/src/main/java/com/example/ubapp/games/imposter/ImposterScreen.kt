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
                               onClick = { selectedCategory = null }, label = { Text("Random") })
                    for (c in e.availableCategories.sorted()) {
                        FilterChip(selected = selectedCategory == c,
                                   onClick = { selectedCategory = c }, label = { Text(c) })
                    }
                }
                Button(onClick = { server.hostStart(selectedCategory) }, enabled = e.canStart) {
                    Text(if (e.canStart) "Start round" else "Need 3+ players")
                }
            }
            ImposterPhase.PLAYING -> {
                ElevatedCard {
                    Column(Modifier.padding(16.dp)) {
                        Text("Category: ${e.category}", style = MaterialTheme.typography.titleMedium)
                        if (e.players[ImposterServer.HOST_ID]?.isImposter == true) {
                            Text("IMPOSTER",
                                 style = MaterialTheme.typography.displaySmall,
                                 color = Color.Red, fontWeight = FontWeight.Bold)
                            Text("Bluff your way through.")
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
                val imp = e.imposterId?.let { e.players[it]?.name }
                if (imp != null) Text("The imposter was $imp.")
                Text("Word: ${e.secretWord}  ·  Category: ${e.category}",
                     style = MaterialTheme.typography.bodySmall)
                Button(onClick = { server.hostNewRound() }) { Text("New round") }
            }
        }
    }
}
