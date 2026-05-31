package com.example.jamboree.games.mafia

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.theme.ubCard
import com.example.jamboree.join.GuestContext
import com.example.jamboree.shared.HostingChrome
import com.example.jamboree.settings.AppSettings
import com.example.jamboree.tutorials.GameTutorials
import com.example.jamboree.tutorials.TutorialVoteCard
import com.example.jamboree.tutorials.snapshot

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
    val server = remember { MafiaServer(ctx, AppSettings.hostName(ctx)) }
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

    JamboreeTheme {
    if (engine.phase == MafiaPhase.LOBBY) {
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
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                   verticalArrangement = Arrangement.spacedBy(4.dp)) {
                MonoLabel("Hosting · Mafia", color = Ub.Accent)
                Text("Waiting for players", fontSize = 24.sp,
                     fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.6).sp, color = Ub.Foreground)
            }
            HostingChrome(
                joinUrl = joinUrl,
                onStart = { joinUrl = server.start() },
                onStop = { server.stop(); joinUrl = null },
            )
            TutorialVoteCard(
                state = engine.tutorialVote.snapshot(),
                tutorial = GameTutorials.mafia,
                onCall = server::hostCallTutorialVote,
                onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MonoLabel("Players · ${engine.players.size}")
                for (p in engine.players.values.sortedBy { it.id }) {
                    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Avatar(p.name, host = p.isHost, size = 30.dp)
                        Spacer(Modifier.width(12.dp))
                        Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                        Spacer(Modifier.weight(1f))
                        if (p.isHost) MonoLabel("host", size = 9, color = Ub.Faint)
                    }
                }
            }
            MafiaOptionsCard(engine, server)
            if (engine.canStart) {
                UbPrimaryButton("Start round · ${engine.players.size} players",
                                onClick = { server.hostStart() })
            } else {
                Text("Need at least 4 players to start.", fontSize = 13.sp, color = Ub.Muted)
            }
        }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { MafiaGuestScreen(loopCtx) }
            if (engine.phase == MafiaPhase.DAY_REVEAL) {
                UbPrimaryButton("Continue to day vote",
                                modifier = Modifier.fillMaxWidth().padding(20.dp),
                                onClick = { server.advanceFromReveal() })
            }
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
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Options")
        Column(Modifier.fillMaxWidth().ubCard().padding(14.dp),
               verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
