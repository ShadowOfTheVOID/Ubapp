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
import com.example.ubapp.join.GuestContext
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

/**
 * Host screen. Lobby is host-owned (QR, team/spymaster, options, "Start
 * round"); once the round starts the host plays on the same
 * [CodenamesGuestScreen] every guest sees, via an in-process loopback, plus
 * a "New game" control the player screen lacks.
 */
@Composable
fun CodenamesScreen() {
    val ctx = LocalContext.current
    val server = remember { CodenamesServer(ctx) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "codenames", CodenamesServer.HOST_ID, server.hostName, emptyList())
    }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    val hostPlayer = e.players[CodenamesServer.HOST_ID]
    val hostIsAnySpymaster = hostPlayer?.isSpymaster == true

    if (e.phase == CodenamesPhase.LOBBY) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            HostingChrome(
                joinUrl = joinUrl,
                onStart = { joinUrl = server.start() },
                onStop = { server.stop(); joinUrl = null },
            )
            Text("Lobby", style = MaterialTheme.typography.titleMedium)
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
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { CodenamesGuestScreen(loopCtx) }
            if (e.phase == CodenamesPhase.GAME_OVER) {
                Button(onClick = { server.hostNewGame() },
                       modifier = Modifier.fillMaxWidth().padding(16.dp)) { Text("New game") }
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
