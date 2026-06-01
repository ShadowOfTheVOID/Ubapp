package com.example.jamboree.games.werewolf

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
import com.example.jamboree.theme.ubCard
import com.example.jamboree.join.GuestContext
import com.example.jamboree.shared.HostingChrome
import com.example.jamboree.settings.AppSettings
import com.example.jamboree.tutorials.GameTutorials
import com.example.jamboree.tutorials.TutorialVoteCard
import com.example.jamboree.tutorials.snapshot

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

    JamboreeTheme {
    if (e.phase == WerewolfPhase.LOBBY) {
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
            LobbyHeader("Werewolf")
            HostingChrome(
                joinUrl = joinUrl,
                onStart = { joinUrl = server.start() },
                onStop = { server.stop(); joinUrl = null },
            )
            TutorialVoteCard(
                state = e.tutorialVote.snapshot(), tutorial = GameTutorials.werewolf,
                onCall = server::hostCallTutorialVote, onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MonoLabel("Players · ${e.players.size}")
                for (p in e.players.values.sortedBy { it.id }) LobbyPlayerRow(p.name, p.isHost)
            }
            WerewolfOptionsCard(e, server)
            if (e.canStart) {
                UbPrimaryButton("Start round · ${e.players.size} players",
                                onClick = { server.hostStart() })
            } else {
                Text("Need at least 5 players to start.", fontSize = 13.sp, color = Ub.Muted)
            }
        }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { WerewolfGuestScreen(loopCtx) }
            if (e.phase == WerewolfPhase.DAY_REVEAL) {
                UbPrimaryButton("Continue to day vote",
                                modifier = Modifier.fillMaxWidth().padding(20.dp),
                                onClick = { server.advanceFromReveal() })
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
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Options")
        Column(Modifier.fillMaxWidth().ubCard().padding(14.dp),
               verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
