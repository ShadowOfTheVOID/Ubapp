package com.example.jamboree.games.codenames

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.border
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.LobbyHeader
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
 * Host screen. Lobby is host-owned (QR, team/spymaster, options, "Start
 * round"); once the round starts the host plays on the same
 * [CodenamesGuestScreen] every guest sees, via an in-process loopback, plus
 * a "New game" control the player screen lacks.
 */
@Composable
fun CodenamesScreen() {
    val ctx = LocalContext.current
    val server = remember { CodenamesServer(ctx, AppSettings.hostName(ctx)) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "codenames", CodenamesServer.HOST_ID, server.hostName, emptyList())
    }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    val hostPlayer = e.players[CodenamesServer.HOST_ID]
    val hostIsAnySpymaster = hostPlayer?.isSpymaster == true

    JamboreeTheme {
    if (e.phase == CodenamesPhase.LOBBY) {
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
            LobbyHeader("Codenames")
            HostingChrome(
                joinUrl = joinUrl,
                onStart = { joinUrl = server.start() },
                onStop = { server.stop(); joinUrl = null },
            )
            TutorialVoteCard(
                state = e.tutorialVote.snapshot(), tutorial = GameTutorials.codenames,
                onCall = server::hostCallTutorialVote, onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TeamButton("Join Red", cnRed, Modifier.weight(1f)) { server.hostJoinTeam(Team.RED) }
                TeamButton("Join Blue", cnBlue, Modifier.weight(1f)) { server.hostJoinTeam(Team.BLUE) }
            }
            Row(Modifier.fillMaxWidth().ubCard().padding(horizontal = 14.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("I'm spymaster ★", Modifier.weight(1f), fontSize = 15.sp, color = Ub.Foreground)
                Switch(checked = hostIsAnySpymaster, onCheckedChange = { server.hostSetSpymaster(it) })
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MonoLabel("Players · ${e.players.size}")
                for (p in e.players.values.sortedBy { it.id }) {
                    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Avatar(p.name, host = p.isHost, size = 30.dp)
                        Spacer(Modifier.width(12.dp))
                        Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                        if (p.isSpymaster) {
                            Spacer(Modifier.width(8.dp))
                            MonoLabel("spy ★", size = 9,
                                      color = if (p.team == Team.RED) cnRed else if (p.team == Team.BLUE) cnBlue else Ub.Faint)
                        }
                        Spacer(Modifier.weight(1f))
                        p.team?.let {
                            MonoLabel(it.name2, size = 9, color = if (it == Team.RED) cnRed else cnBlue)
                        }
                    }
                }
            }
            CodenamesOptionsCard(e, server)
            if (e.canStart) {
                UbPrimaryButton("Start round", onClick = { server.hostStart() })
            } else {
                Text("Need ≥2 per team with a spymaster on each side.", fontSize = 13.sp, color = Ub.Muted)
            }
        }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { CodenamesGuestScreen(loopCtx) }
            if (e.phase == CodenamesPhase.GAME_OVER) {
                UbPrimaryButton("Rematch · swap teams",
                                modifier = Modifier.fillMaxWidth().padding(20.dp),
                                onClick = { server.hostNewGame() })
            }
        }
    }
    }
}

private val cnRed = Color(0xFFFF5A4A)
private val cnBlue = Color(0xFF4F9EFF)

@Composable
private fun TeamButton(title: String, color: Color, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier
        .clip(RoundedCornerShape(Ub.Radius.button))
        .background(color.copy(alpha = 0.12f))
        .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(Ub.Radius.button))
        .clickable(onClick = onClick)
        .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center) {
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = color)
    }
}

@Composable
private fun CodenamesOptionsCard(engine: CodenamesEngine, server: CodenamesServer) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Options")
        Column(Modifier.fillMaxWidth().ubCard().padding(14.dp),
               verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Board size:", Modifier.weight(1f))
                for (n in CodenamesOptions.allowedSizes) {
                    val selected = engine.options.boardSize == n
                    FilterChip(selected = selected,
                               onClick = { server.hostSetOptions(engine.options.copy(boardSize = n)) },
                               label = { Text("$n") },
                               modifier = Modifier.padding(start = 4.dp))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Assassins: ${engine.options.assassinCount}", Modifier.weight(1f))
                IconButton(onClick = {
                    server.hostSetOptions(engine.options.copy(
                        assassinCount = (engine.options.assassinCount - 1).coerceAtLeast(1)))
                }, enabled = engine.options.assassinCount > 1) {
                    Text("−", style = MaterialTheme.typography.titleLarge)
                }
                IconButton(onClick = {
                    server.hostSetOptions(engine.options.copy(
                        assassinCount = (engine.options.assassinCount + 1).coerceAtMost(3)))
                }, enabled = engine.options.assassinCount < 3) {
                    Text("+", style = MaterialTheme.typography.titleLarge)
                }
            }
        }
    }
}
