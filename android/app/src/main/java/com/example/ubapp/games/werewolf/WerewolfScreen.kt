package com.example.ubapp.games.werewolf

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

/**
 * Host screen. Lobby is host-owned (QR, options, "Start round"); once the
 * round starts the host plays on the same [WerewolfGuestScreen] every guest
 * sees, via an in-process loopback, plus a control bar to advance past the
 * night reveal.
 */
@Composable
fun WerewolfScreen() {
    val ctx = LocalContext.current
    val server = remember { WerewolfServer(ctx, AppSettings.hostName(ctx)) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "werewolf", WerewolfServer.HOST_ID, server.hostName, emptyList())
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
    if (e.phase == WerewolfPhase.LOBBY) {
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
                state = e.tutorialVote.snapshot(), tutorial = GameTutorials.werewolf,
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
            WerewolfOptionsCard(e, server)
            Button(onClick = { server.hostStart() }, enabled = e.canStart) {
                Text(if (e.canStart) "Start round" else "Need 5+ players")
            }
        }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { WerewolfGuestScreen(loopCtx) }
            if (e.phase == WerewolfPhase.DAY_REVEAL) {
                Button(
                    onClick = { server.advanceFromReveal() },
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                ) { Text("Continue to day vote") }
            }
        }
    }
    }
}

@Composable
private fun WerewolfOptionsCard(engine: WerewolfEngine, server: WerewolfServer) {
    val auto = engine.options.wolfCount == null
    val maxCount = engine.maxWolfCount
    val current = engine.options.wolfCount
        ?: (engine.players.size / 5).coerceIn(1, maxOf(1, engine.players.size - 3))
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Options", style = MaterialTheme.typography.titleSmall)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = auto, onCheckedChange = { on ->
                    server.hostSetOptions(engine.options.copy(
                        wolfCount = if (on) null else current.coerceIn(1, maxCount)
                    ))
                })
                Text("  Auto-balance wolf count")
            }
            if (!auto) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Wolves: $current", Modifier.weight(1f))
                    IconButton(onClick = {
                        server.hostSetOptions(engine.options.copy(
                            wolfCount = (current - 1).coerceAtLeast(1)))
                    }, enabled = current > 1) {
                        Text("−", style = MaterialTheme.typography.titleLarge)
                    }
                    IconButton(onClick = {
                        server.hostSetOptions(engine.options.copy(
                            wolfCount = (current + 1).coerceAtMost(maxCount)))
                    }, enabled = current < maxCount) {
                        Text("+", style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = engine.options.seerEnabled,
                       onCheckedChange = { server.hostSetOptions(engine.options.copy(seerEnabled = it)) })
                Text("  Seer")
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = engine.options.hunterEnabled,
                       onCheckedChange = { server.hostSetOptions(engine.options.copy(hunterEnabled = it)) })
                Text("  Hunter (6+ players)")
            }
        }
    }
}
