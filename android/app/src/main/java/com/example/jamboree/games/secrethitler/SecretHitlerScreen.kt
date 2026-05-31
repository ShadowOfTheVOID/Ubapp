package com.example.jamboree.games.secrethitler

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.theme.LobbyHeader
import com.example.jamboree.theme.LobbyPlayerRow
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.join.GuestContext
import com.example.jamboree.shared.HostingChrome
import com.example.jamboree.settings.AppSettings
import com.example.jamboree.tutorials.GameTutorials
import com.example.jamboree.tutorials.TutorialVoteCard
import com.example.jamboree.tutorials.snapshot

/**
 * Host screen. Lobby is host-owned (QR, "Start round"); once the round starts
 * the host plays on the same [SecretHitlerGuestScreen] every guest sees, via
 * an in-process loopback — every per-phase action (nominate, vote, discard,
 * enact, veto, peek, investigate, execute) is already player-driven.
 */
@Composable
fun SecretHitlerScreen() {
    val ctx = LocalContext.current
    val server = remember { SecretHitlerServer(ctx, AppSettings.hostName(ctx)) }
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

    JamboreeTheme {
    if (engine.phase == SecretHitlerPhase.LOBBY) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            LobbyHeader("Secret Hitler")
            HostingChrome(
                joinUrl = joinUrl,
                onStart = { joinUrl = server.start() },
                onStop = { server.stop(); joinUrl = null },
            )
            TutorialVoteCard(
                state = engine.tutorialVote.snapshot(),
                tutorial = GameTutorials.secretHitler,
                onCall = server::hostCallTutorialVote,
                onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MonoLabel("Players · ${engine.players.size}")
                for (id in engine.seatOrder) {
                    val p = engine.players[id] ?: continue
                    LobbyPlayerRow(p.name, p.isHost)
                }
            }
            if (engine.canStart) {
                UbPrimaryButton("Start round · ${engine.players.size} players",
                                onClick = { server.hostStart() })
            } else {
                Text("Need 5–10 players to start.", fontSize = 13.sp, color = Ub.Muted)
            }
        }
        }
    } else {
        SecretHitlerGuestScreen(loopCtx)
    }
    }
}
