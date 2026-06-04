package com.example.jamboree.games.president

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
import com.example.jamboree.theme.UbSecondaryButton
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.theme.ubCard
import com.example.jamboree.join.GuestContext
import com.example.jamboree.shared.HostingChrome
import com.example.jamboree.settings.AppSettings
import com.example.jamboree.tutorials.GameTutorials
import com.example.jamboree.tutorials.TutorialVoteCard
import com.example.jamboree.tutorials.snapshot

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
        server.onStopped = { joinUrl = null }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    JamboreeTheme {
        if (e.phase == PresidentPhase.LOBBY) {
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
                    LobbyHeader("President")
                    HostingChrome(
                        joinUrl = joinUrl,
                        onStart = { joinUrl = server.start() },
                        onStop = { server.stop(); joinUrl = null },
                    )
                    TutorialVoteCard(
                        state = e.tutorialVote.snapshot(), tutorial = GameTutorials.president,
                        onCall = server::hostCallTutorialVote, onVote = server::hostTutorialVote,
                        onDismiss = server::hostDismissTutorial,
                    )
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MonoLabel("Players · ${e.players.size}")
                        for (p in e.players.values.sortedBy { it.id }) LobbyPlayerRow(p.name, p.isHost)
                    }
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MonoLabel("Options")
                        Column(Modifier.fillMaxWidth().ubCard().padding(14.dp),
                               verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
                    if (e.canStart) {
                        UbPrimaryButton("Start round · ${e.players.size} players",
                                        onClick = { server.hostStart() })
                    } else {
                        Text("Need 4–7 players to start.", fontSize = 13.sp, color = Ub.Muted)
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { PresidentGuestScreen(loopCtx) }
                if (e.phase == PresidentPhase.GAME_OVER) {
                    Row(modifier = Modifier.fillMaxWidth().padding(20.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        UbSecondaryButton("New game", modifier = Modifier.weight(1f),
                            onClick = { server.hostNewGame() })
                        UbPrimaryButton("Next round", modifier = Modifier.weight(1f),
                            onClick = { server.hostNextRound() })
                    }
                }
            }
        }
    }
}
