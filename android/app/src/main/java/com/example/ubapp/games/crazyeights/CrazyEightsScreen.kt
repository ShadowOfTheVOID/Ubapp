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
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

@Composable
fun CrazyEightsScreen() {
    val ctx = LocalContext.current
    val server = remember { CrazyEightsServer(ctx) }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    var pendingEight by remember { mutableStateOf<Card?>(null) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    val hostHand = e.players[CrazyEightsServer.HOST_ID]?.hand.orEmpty()
    val hostIsCurrent = e.current?.id == CrazyEightsServer.HOST_ID

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HostingChrome(joinUrl) { joinUrl = server.start() }
        Text("Phase: ${e.phase}", style = MaterialTheme.typography.titleMedium)

        when (e.phase) {
            CrazyEightsPhase.LOBBY -> {
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
            CrazyEightsPhase.PLAYING -> {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    e.topCard?.let { CardChip(it, faded = false) }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Active: ${e.activeSuit?.glyph ?: e.topCard?.suit?.glyph ?: "—"}")
                        Text("Turn: ${e.current?.name.orEmpty()}",
                             style = MaterialTheme.typography.bodySmall)
                    }
                    OutlinedButton(onClick = { server.hostDraw() }, enabled = hostIsCurrent) {
                        Text("Draw (${e.drawPile.size})")
                    }
                }
                e.lastEvent?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                if (e.justDrew && hostIsCurrent) {
                    OutlinedButton(onClick = { server.hostPass() }) { Text("Pass") }
                }
                Text("Your hand (${hostHand.size})", style = MaterialTheme.typography.titleSmall)
                LazyVerticalGrid(
                    columns = GridCells.Fixed(5),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.heightIn(max = 400.dp),
                ) {
                    itemsIndexed(hostHand) { _, c ->
                        val playable = hostIsCurrent && e.canPlay(c)
                        Box(Modifier.alpha(if (playable) 1f else 0.4f)
                                    .clickable(enabled = playable) {
                                        if (c.rank == 8) pendingEight = c
                                        else server.hostPlay(c, null)
                                    }) {
                            CardChip(c, faded = !playable)
                        }
                    }
                }
            }
            CrazyEightsPhase.GAME_OVER -> {
                val w = e.winnerId?.let { e.players[it]?.name }
                Text(if (w != null) "$w wins" else "Game over",
                     style = MaterialTheme.typography.headlineSmall)
                for (p in e.players.values) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(p.name); Text("${p.hand.size} cards left")
                    }
                }
                Button(onClick = { server.hostNewGame() }) { Text("New game") }
            }
        }
    }

    val pe = pendingEight
    if (pe != null) {
        AlertDialog(
            onDismissRequest = { pendingEight = null },
            title = { Text("Declare suit") },
            text = {
                Column {
                    for (s in Suit.entries) {
                        TextButton(onClick = {
                            server.hostPlay(pe, s)
                            pendingEight = null
                        }) { Text("${s.glyph} ${s.name.lowercase().replaceFirstChar { it.uppercase() }}") }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { pendingEight = null }) { Text("Cancel") } },
        )
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
