package com.example.ubapp.games.codenames

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

@Composable
fun CodenamesScreen() {
    val ctx = LocalContext.current
    val server = remember { CodenamesServer(ctx) }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    var clueDraft by remember { mutableStateOf("") }
    var clueNumber by remember { mutableIntStateOf(1) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    val hostPlayer = e.players[CodenamesServer.HOST_ID]
    val hostIsAnySpymaster = hostPlayer?.isSpymaster == true
    val hostIsCurrentSpymaster = hostIsAnySpymaster && hostPlayer?.team == e.currentTeam

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HostingChrome(
            joinUrl = joinUrl,
            onStart = { joinUrl = server.start() },
            onStop = { server.stop(); joinUrl = null },
        )
        Text("Phase: ${e.phase}", style = MaterialTheme.typography.titleMedium)

        when (e.phase) {
            CodenamesPhase.LOBBY -> {
                TutorialVoteCard(
                    state = e.tutorialVote.snapshot(), tutorial = GameTutorials.codenames,
                    onCall = server::hostCallTutorialVote, onVote = server::hostTutorialVote,
                    onDismiss = server::hostDismissTutorial,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { server.hostJoinTeam(Team.RED) },
                        colors = ButtonDefaults.buttonColors(containerColor = Color.Red),
                        modifier = Modifier.weight(1f),
                    ) { Text("Join Red") }
                    Button(
                        onClick = { server.hostJoinTeam(Team.BLUE) },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2)),
                        modifier = Modifier.weight(1f),
                    ) { Text("Join Blue") }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(checked = hostIsAnySpymaster,
                           onCheckedChange = { server.hostSetSpymaster(it) })
                    Spacer(Modifier.width(8.dp))
                    Text("I'm spymaster")
                }
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Players", style = MaterialTheme.typography.titleSmall)
                        for (p in e.players.values.sortedBy { it.id }) {
                            Row(Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(p.name)
                                Text((p.team?.name2 ?: "—") + if (p.isSpymaster) " (SM)" else "",
                                     color = when (p.team) {
                                         Team.RED -> Color.Red
                                         Team.BLUE -> Color(0xFF1976D2)
                                         null -> Color.Gray
                                     })
                            }
                        }
                    }
                }
                CodenamesOptionsCard(e, server)
                Button(onClick = { server.hostStart() }, enabled = e.canStart) {
                    Text(if (e.canStart) "Start round"
                         else "Need ≥2 per team with a spymaster on each")
                }
            }
            CodenamesPhase.PLAYING -> {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Turn: ${e.currentTeam.name2.replaceFirstChar { it.uppercase() }}",
                         color = if (e.currentTeam == Team.RED) Color.Red else Color(0xFF1976D2))
                    Text("Red ${e.cardsLeftFor(Team.RED)} · Blue ${e.cardsLeftFor(Team.BLUE)}")
                }
                val clue = e.currentClue
                if (clue != null) {
                    Text("${clue.uppercase()} · ${e.currentNumber}",
                         style = MaterialTheme.typography.headlineSmall)
                    if (e.guessesLeftThisTurn > 0)
                        Text("${e.guessesLeftThisTurn} guesses left",
                             style = MaterialTheme.typography.bodySmall)
                } else if (hostIsCurrentSpymaster) {
                    OutlinedTextField(value = clueDraft, onValueChange = { clueDraft = it },
                                      label = { Text("Clue word") })
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Number: $clueNumber"); Spacer(Modifier.width(8.dp))
                        OutlinedButton(onClick = { if (clueNumber > 0) clueNumber-- }) { Text("-") }
                        OutlinedButton(onClick = { if (clueNumber < 9) clueNumber++ }) { Text("+") }
                    }
                    Button(
                        onClick = {
                            val c = clueDraft.trim()
                            if (c.isNotEmpty()) { server.hostSubmitClue(c, clueNumber); clueDraft = "" }
                        },
                        enabled = clueDraft.isNotBlank(),
                    ) { Text("Send clue") }
                }

                LazyVerticalGrid(
                    columns = GridCells.Fixed(5),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.heightIn(max = 600.dp),
                ) {
                    itemsIndexed(e.board) { i, c ->
                        val bg = if (c.revealed) when (c.kind) {
                            CardKind.RED -> Color.Red
                            CardKind.BLUE -> Color(0xFF1976D2)
                            CardKind.NEUTRAL -> Color.Gray
                            CardKind.ASSASSIN -> Color.Black
                        } else if (hostIsAnySpymaster) when (c.kind) {
                            CardKind.RED -> Color.Red.copy(alpha = 0.4f)
                            CardKind.BLUE -> Color(0xFF1976D2).copy(alpha = 0.4f)
                            CardKind.NEUTRAL -> Color.Gray.copy(alpha = 0.3f)
                            CardKind.ASSASSIN -> Color.Black.copy(alpha = 0.5f)
                        } else Color.Gray.copy(alpha = 0.3f)
                        val enabled = !c.revealed && !hostIsCurrentSpymaster &&
                                      e.currentClue != null && e.guessesLeftThisTurn > 0
                        Box(
                            Modifier.heightIn(min = 56.dp).fillMaxWidth()
                                .clip(RoundedCornerShape(6.dp))
                                .background(bg)
                                .let { if (enabled) it.clickable { server.hostGuess(i) } else it }
                                .padding(4.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(c.word, color = Color.White, textAlign = TextAlign.Center,
                                 style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }

                if (!hostIsCurrentSpymaster && e.currentClue != null &&
                    e.guessesLeftThisTurn != e.currentNumber + 1) {
                    OutlinedButton(onClick = { server.hostEndTurn() }) { Text("End turn") }
                }
            }
            CodenamesPhase.GAME_OVER -> {
                Text("${e.winner?.name2?.uppercase() ?: "?"} wins",
                     style = MaterialTheme.typography.headlineSmall)
                e.endReason?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                Button(onClick = { server.hostNewGame() }) { Text("New game") }
            }
        }
    }
}

@Composable
private fun CodenamesOptionsCard(engine: CodenamesEngine, server: CodenamesServer) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Options", style = MaterialTheme.typography.titleSmall)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Board size:", Modifier.weight(1f))
                for (n in CodenamesOptions.allowedSizes) {
                    val selected = engine.options.boardSize == n
                    FilterChip(selected = selected,
                               onClick = { server.hostSetOptions(engine.options.copy(boardSize = n)) },
                               label = { Text("$n") },
                               modifier = Modifier.padding(start = 4.dp))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Assassins: ${engine.options.assassinCount}", Modifier.weight(1f))
                IconButton(onClick = {
                    server.hostSetOptions(engine.options.copy(
                        assassinCount = (engine.options.assassinCount - 1).coerceAtLeast(1)))
                }, enabled = engine.options.assassinCount > 1) {
                    Text("−", style = MaterialTheme.typography.titleLarge)
                }
                IconButton(onClick = {
                    server.hostSetOptions(engine.options.copy(
                        assassinCount = (engine.options.assassinCount + 1).coerceAtMost(3)))
                }, enabled = engine.options.assassinCount < 3) {
                    Text("+", style = MaterialTheme.typography.titleLarge)
                }
            }
        }
    }
}
