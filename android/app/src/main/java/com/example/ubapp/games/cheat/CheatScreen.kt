package com.example.ubapp.games.cheat

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
fun CheatScreen() {
    val ctx = LocalContext.current
    val server = remember { CheatServer(ctx, AppSettings.hostName(ctx)) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "cheat", CheatServer.HOST_ID, server.hostName, emptyList())
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
        if (e.phase == CheatPhase.LOBBY) {
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
                        state = e.tutorialVote.snapshot(), tutorial = GameTutorials.cheat,
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
                                Switch(checked = e.options.freeClaim,
                                       onCheckedChange = { server.hostSetOptions(e.options.copy(freeClaim = it)) })
                                Text("  Free claim (any rank, no sequence)")
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Switch(checked = e.options.randomStartRank,
                                       onCheckedChange = { server.hostSetOptions(e.options.copy(randomStartRank = it)) },
                                       enabled = !e.options.freeClaim)
                                Text("  Random starting rank")
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Switch(checked = e.options.descending,
                                       onCheckedChange = { server.hostSetOptions(e.options.copy(descending = it)) },
                                       enabled = !e.options.freeClaim)
                                Text("  Count ranks downward")
                            }
                        }
                    }
                    Button(onClick = { server.hostStart() }, enabled = e.canStart) {
                        Text(if (e.canStart) "Start round" else "Need 3–8 players")
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { CheatGuestScreen(loopCtx) }
                if (e.phase == CheatPhase.GAME_OVER) {
                    Button(onClick = { server.hostNewGame() },
                           modifier = Modifier.fillMaxWidth().padding(16.dp)) { Text("New game") }
                }
            }
        }
    }
}
