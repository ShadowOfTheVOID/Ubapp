package com.example.ubapp.games.crazyeights

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.theme.Avatar
import com.example.ubapp.theme.MonoLabel
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.UbPrimaryButton
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.theme.ubCard
import com.example.ubapp.join.GuestContext
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.settings.AppSettings
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

/**
 * Host screen. Lobby is host-owned (QR, options, "Start round"); once the
 * round starts the host plays on the same [CrazyEightsGuestScreen] every
 * guest sees, via an in-process loopback, plus a "New game" control the
 * player screen lacks.
 */
@Composable
fun CrazyEightsScreen() {
    val ctx = LocalContext.current
    val server = remember { CrazyEightsServer(ctx, AppSettings.hostName(ctx)) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "crazy_eights", CrazyEightsServer.HOST_ID, server.hostName, emptyList())
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
    if (e.phase == CrazyEightsPhase.LOBBY) {
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
                MonoLabel("Hosting · Crazy 8s", color = Ub.Accent)
                Text("Waiting for players", fontSize = 24.sp,
                     fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.6).sp, color = Ub.Foreground)
            }
            HostingChrome(
                joinUrl = joinUrl,
                onStart = { joinUrl = server.start() },
                onStop = { server.stop(); joinUrl = null },
            )
            TutorialVoteCard(
                state = e.tutorialVote.snapshot(), tutorial = GameTutorials.crazyEights,
                onCall = server::hostCallTutorialVote, onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MonoLabel("Players · ${e.players.size}")
                for (p in e.players.values.sortedBy { it.id }) {
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
            CrazyEightsOptionsCard(e, server)
            if (e.canStart) {
                UbPrimaryButton("Start round · ${e.players.size} players",
                                onClick = { server.hostStart() })
            } else {
                Text("Need 2–8 players to start.", fontSize = 13.sp, color = Ub.Muted)
            }
        }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { CrazyEightsGuestScreen(loopCtx) }
            if (e.phase == CrazyEightsPhase.GAME_OVER) {
                UbPrimaryButton("Rematch · same room",
                                modifier = Modifier.fillMaxWidth().padding(20.dp),
                                onClick = { server.hostNewGame() })
            }
        }
    }
    }
}

@Composable
private fun CrazyEightsOptionsCard(engine: CrazyEightsEngine, server: CrazyEightsServer) {
    val custom = engine.options.startingHandSize != null
    val current = engine.options.startingHandSize
        ?: if (engine.players.size == 2) 7 else 5
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Options")
        Column(Modifier.fillMaxWidth().ubCard().padding(14.dp),
               verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = custom, onCheckedChange = { on ->
                    server.hostSetOptions(engine.options.copy(
                        startingHandSize = if (on) current.coerceIn(3, 10) else null
                    ))
                })
                Text("  Custom starting hand")
            }
            if (custom) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Hand: $current", Modifier.weight(1f))
                    IconButton(onClick = {
                        server.hostSetOptions(engine.options.copy(
                            startingHandSize = (current - 1).coerceAtLeast(3)))
                    }, enabled = current > 3) {
                        Text("−", style = MaterialTheme.typography.titleLarge)
                    }
                    IconButton(onClick = {
                        server.hostSetOptions(engine.options.copy(
                            startingHandSize = (current + 1).coerceAtMost(10)))
                    }, enabled = current < 10) {
                        Text("+", style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = engine.options.jackSkips,
                       onCheckedChange = { server.hostSetOptions(engine.options.copy(jackSkips = it)) })
                Text("  Jacks skip next player")
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = engine.options.queenReverses,
                       onCheckedChange = { server.hostSetOptions(engine.options.copy(queenReverses = it)) })
                Text("  Queens reverse direction")
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = engine.options.twosDrawTwo,
                       onCheckedChange = { server.hostSetOptions(engine.options.copy(twosDrawTwo = it)) })
                Text("  Twos: next player draws two")
            }
        }
    }
}

@Composable
private fun CardChip(c: Card, faded: Boolean) {
    Column(
        Modifier.size(48.dp, 64.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .alpha(if (faded) 0.4f else 1f)
            .padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(c.rankShort,
             color = if (c.suit.isRed) Color.Red else Color.Black,
             fontWeight = FontWeight.Bold)
        Text(c.suit.glyph,
             color = if (c.suit.isRed) Color.Red else Color.Black)
    }
}
