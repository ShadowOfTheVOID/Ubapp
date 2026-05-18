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
import com.example.ubapp.theme.UbappTheme
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
                state = e.tutorialVote.snapshot(), tutorial = GameTutorials.crazyEights,
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
            CrazyEightsOptionsCard(e, server)
            Button(onClick = { server.hostStart() }, enabled = e.canStart) {
                Text(if (e.canStart) "Start round" else "Need 2–8 players")
            }
        }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) { CrazyEightsGuestScreen(loopCtx) }
            if (e.phase == CrazyEightsPhase.GAME_OVER) {
                Button(onClick = { server.hostNewGame() },
                       modifier = Modifier.fillMaxWidth().padding(16.dp)) { Text("New game") }
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
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Options", style = MaterialTheme.typography.titleSmall)
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
