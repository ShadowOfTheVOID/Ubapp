package com.example.ubapp.games.imposter

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.join.GuestContext
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.settings.AppSettings
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

/**
 * Host screen. Lobby is host-owned (QR, category, options, "Start round");
 * once the round starts the host plays on the same [ImposterGuestScreen]
 * every guest sees, via an in-process loopback, plus a control bar for the
 * host-only orchestration the player screen lacks (call vote / new round).
 */
@Composable
fun ImposterScreen() {
    val ctx = LocalContext.current
    val server = remember { ImposterServer(ctx, AppSettings.hostName(ctx)) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "imposter", ImposterServer.HOST_ID, server.hostName, emptyList())
    }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    var selectedCategory by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    UbappTheme {
    if (e.phase == ImposterPhase.LOBBY) {
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
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { ImposterGuestScreen(loopCtx) }
            when (e.phase) {
                ImposterPhase.PLAYING ->
                    Button(onClick = { server.hostBeginVoting() },
                           modifier = Modifier.fillMaxWidth().padding(16.dp)) { Text("Call vote") }
                ImposterPhase.RESULT, ImposterPhase.GAME_OVER ->
                    Button(onClick = { server.hostNewRound() },
                           modifier = Modifier.fillMaxWidth().padding(16.dp)) { Text("New round") }
                else -> {}
            }
        }
    }
    }
}
