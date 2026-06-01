package com.example.jamboree.games.cheat

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

    JamboreeTheme {
        if (e.phase == CheatPhase.LOBBY) {
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
                    LobbyHeader("Cheat")
                    HostingChrome(
                        joinUrl = joinUrl,
                        onStart = { joinUrl = server.start() },
                        onStop = { server.stop(); joinUrl = null },
                    )
                    TutorialVoteCard(
                        state = e.tutorialVote.snapshot(), tutorial = GameTutorials.cheat,
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
                    if (e.canStart) {
                        UbPrimaryButton("Start round · ${e.players.size} players",
                                        onClick = { server.hostStart() })
                    } else {
                        Text("Need 3–8 players to start.", fontSize = 13.sp, color = Ub.Muted)
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { CheatGuestScreen(loopCtx) }
                if (e.phase == CheatPhase.GAME_OVER) {
                    UbPrimaryButton("Rematch · same room",
                                    modifier = Modifier.fillMaxWidth().padding(20.dp),
                                    onClick = { server.hostNewGame() })
                }
            }
        }
    }
}
