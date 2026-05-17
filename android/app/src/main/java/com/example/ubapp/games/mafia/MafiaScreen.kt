package com.example.ubapp.games.mafia

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.join.GuestContext
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

/**
 * Host screen. The lobby is host-owned (QR, options, "Start round"); once the
 * round starts the host plays on the *exact same* player screen every guest
 * sees ([MafiaGuestScreen]), driven by an in-process loopback as the `host`
 * player — plus a control bar for the one orchestration step the player
 * screen lacks (advancing past the night reveal).
 */
@Composable
fun MafiaScreen() {
    val ctx = LocalContext.current
    val server = remember { MafiaServer(ctx) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "mafia", MafiaServer.HOST_ID, server.hostName, emptyList())
    }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val engine = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    if (engine.phase == MafiaPhase.LOBBY) {
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
                state = engine.tutorialVote.snapshot(),
                tutorial = GameTutorials.mafia,
                onCall = server::hostCallTutorialVote,
                onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("Players (${engine.players.size})",
                         style = MaterialTheme.typography.titleSmall)
                    for (p in engine.players.values.sortedBy { it.id }) {
                        Text(p.name + if (p.isHost) " (host)" else "")
                    }
                }
            }
            MafiaOptionsCard(engine, server)
            Button(onClick = { server.hostStart() }, enabled = engine.canStart) {
                Text(if (engine.canStart) "Start round" else "Need 4+ players")
            }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { MafiaGuestScreen(loopCtx) }
            if (engine.phase == MafiaPhase.DAY_REVEAL) {
                Button(
                    onClick = { server.advanceFromReveal() },
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                ) { Text("Continue to day vote") }
            }
        }
    }
}

@Composable
private fun MafiaOptionsCard(engine: MafiaEngine, server: MafiaServer) {
    val auto = engine.options.mafiaCount == null
    val maxCount = engine.maxMafiaCount
    val current = engine.options.mafiaCount
        ?: (engine.players.size / 4).coerceIn(1, maxOf(1, engine.players.size - 2))
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Options", style = MaterialTheme.typography.titleSmall)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = auto, onCheckedChange = { on ->
                    server.hostSetOptions(engine.options.copy(
                        mafiaCount = if (on) null else current.coerceIn(1, maxCount)
                    ))
                })
                Text("  Auto-balance mafia count")
            }
            if (!auto) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Mafia: $current", Modifier.weight(1f))
                    IconButton(onClick = {
                        server.hostSetOptions(engine.options.copy(
                            mafiaCount = (current - 1).coerceAtLeast(1)))
                    }, enabled = current > 1) {
                        Text("−", style = MaterialTheme.typography.titleLarge)
                    }
                    IconButton(onClick = {
                        server.hostSetOptions(engine.options.copy(
                            mafiaCount = (current + 1).coerceAtMost(maxCount)))
                    }, enabled = current < maxCount) {
                        Text("+", style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = engine.options.doctorEnabled,
                       onCheckedChange = { server.hostSetOptions(engine.options.copy(doctorEnabled = it)) })
                Text("  Doctor")
            }
        }
    }
}
