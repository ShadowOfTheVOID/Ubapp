package com.example.ubapp.games.president

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.join.GuestContext
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.settings.AppSettings
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

@Composable
fun PresidentScreen() {
    val ctx = LocalContext.current
    val server = remember { PresidentServer(ctx, AppSettings.hostName(ctx)) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "president", PresidentServer.HOST_ID, server.hostName, emptyList())
    }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    UbappTheme {
        if (e.phase == PresidentPhase.LOBBY) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    Modifier
                        .verticalScroll(rememberScrollState())
                        .widthIn(max = 480.dp)
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    HostingChrome(
                        joinUrl = joinUrl,
                        onStart = { joinUrl = server.start() },
                        onStop = { server.stop(); joinUrl = null },
                    )
                    Text("Lobby", style = MaterialTheme.typography.titleMedium)
                    TutorialVoteCard(
                        state = e.tutorialVote.snapshot(), tutorial = GameTutorials.president,
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
                    ElevatedCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Options", style = MaterialTheme.typography.titleSmall)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Switch(checked = e.options.allowHouseRules,
                                       onCheckedChange = { server.hostSetOptions(e.options.copy(allowHouseRules = it)) })
                                Text("  Allow President house rules (chat-enforced)")
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Switch(checked = e.options.revolution,
                                       onCheckedChange = { server.hostSetOptions(e.options.copy(revolution = it)) })
                                Text("  Revolution display (no engine effect)")
                            }
                        }
                    }
                    Button(onClick = { server.hostStart() }, enabled = e.canStart) {
                        Text(if (e.canStart) "Start round" else "Need 4–7 players")
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { PresidentGuestScreen(loopCtx) }
                if (e.phase == PresidentPhase.GAME_OVER) {
                    Row(modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { server.hostNextRound() }, modifier = Modifier.weight(1f))
                        { Text("Next round") }
                        OutlinedButton(onClick = { server.hostNewGame() }, modifier = Modifier.weight(1f))
                        { Text("New game") }
                    }
                }
            }
        }
    }
}
