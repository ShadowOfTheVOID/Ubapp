package com.example.ubapp.games.mafia

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

@Composable
fun MafiaScreen() {
    val ctx = LocalContext.current
    val server = remember { MafiaServer(ctx) }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val engine = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HostingChrome(
            joinUrl = joinUrl,
            onStart = { joinUrl = server.start() },
            onStop = { server.stop(); joinUrl = null },
        )

        Text("Phase: ${engine.phase}  · Day ${engine.day}",
             style = MaterialTheme.typography.titleMedium)

        when (engine.phase) {
            MafiaPhase.LOBBY -> {
                TutorialVoteCard(
                    state = engine.tutorialVote.snapshot(),
                    tutorial = GameTutorials.mafia,
                    onCall = server::hostCallTutorialVote,
                    onVote = server::hostTutorialVote,
                    onDismiss = server::hostDismissTutorial,
                )
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Players (${engine.players.size})",
                             style = MaterialTheme.typography.titleSmall)
                        for (p in engine.players.values.sortedBy { it.id }) {
                            Text(p.name + if (p.isHost) " (host)" else "")
                        }
                    }
                }
                MafiaOptionsCard(engine, server)
                Button(onClick = { server.hostStart() }, enabled = engine.canStart) {
                    Text(if (engine.canStart) "Start round" else "Need 4+ players")
                }
            }
            MafiaPhase.NIGHT -> {
                val role = engine.players[MafiaServer.HOST_ID]?.role
                if (role != null) Text("Your role: ${role.displayName} — ${role.tagline}")
                if (role == MafiaRole.MAFIA || role == MafiaRole.DOCTOR) {
                    Text(if (role == MafiaRole.MAFIA) "Pick someone to kill"
                         else "Pick someone to save")
                    val targets = engine.alive.filter {
                        role == MafiaRole.DOCTOR || it.id != MafiaServer.HOST_ID
                    }
                    for (p in targets) {
                        OutlinedButton(
                            onClick = { server.hostNightAction(p.id) },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text(p.name) }
                    }
                } else {
                    Text("Waiting for mafia and doctor to act…")
                }
            }
            MafiaPhase.DAY_REVEAL -> {
                val n = engine.lastNight
                Text(when {
                    n?.killedId != null -> "${engine.players[n.killedId]?.name} was killed."
                    n?.savedId != null -> "The doctor saved someone — no one died."
                    else -> "A quiet night. No one died."
                })
                Button(onClick = { server.advanceFromReveal() }) { Text("Continue to day vote") }
            }
            MafiaPhase.DAY_VOTE -> {
                Text("Vote to eliminate")
                for (p in engine.alive.filter { it.id != MafiaServer.HOST_ID }) {
                    OutlinedButton(onClick = { server.hostDayVote(p.id) },
                                   modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
                OutlinedButton(onClick = { server.hostDayVote(null) },
                               modifier = Modifier.fillMaxWidth()) { Text("Skip vote") }
            }
            MafiaPhase.GAME_OVER -> {
                Text(if (engine.winner == MafiaWinner.TOWN) "Town wins" else "Mafia wins",
                     style = MaterialTheme.typography.headlineSmall)
                for (p in engine.players.values) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(p.name); Text(p.role?.displayName ?: "—")
                    }
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
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Options", style = MaterialTheme.typography.titleSmall)
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
