package com.example.ubapp.games.secrethitler

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.join.GuestContext
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

/**
 * Host screen. Lobby is host-owned (QR, "Start round"); once the round starts
 * the host plays on the same [SecretHitlerGuestScreen] every guest sees, via
 * an in-process loopback — every per-phase action (nominate, vote, discard,
 * enact, veto, peek, investigate, execute) is already player-driven.
 */
@Composable
fun SecretHitlerScreen() {
    val ctx = LocalContext.current
    val server = remember { SecretHitlerServer(ctx) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "secret_hitler", SecretHitlerServer.HOST_ID, server.hostName, emptyList())
    }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val engine = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    if (engine.phase == SecretHitlerPhase.LOBBY) {
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
                tutorial = GameTutorials.secretHitler,
                onCall = server::hostCallTutorialVote,
                onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("Players (${engine.players.size})",
                         style = MaterialTheme.typography.titleSmall)
                    for (id in engine.seatOrder) {
                        val p = engine.players[id] ?: continue
                        Text(p.name + if (p.isHost) " (host)" else "")
                    }
                }
            }
            Button(onClick = { server.hostStart() }, enabled = engine.canStart) {
                Text(if (engine.canStart) "Start round" else "Need 5–10 players")
            }
        }
    } else {
        SecretHitlerGuestScreen(loopCtx)
    }
}
