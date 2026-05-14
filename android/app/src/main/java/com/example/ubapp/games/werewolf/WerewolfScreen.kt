package com.example.ubapp.games.werewolf

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

@Composable
fun WerewolfScreen() {
    val ctx = LocalContext.current
    val server = remember { WerewolfServer(ctx) }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }
    val e = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HostingChrome(joinUrl) { joinUrl = server.start() }

        Text("Phase: ${e.phase}" + if (e.day > 0) "  · Day ${e.day}" else "",
             style = MaterialTheme.typography.titleMedium)

        when (e.phase) {
            WerewolfPhase.LOBBY -> {
                TutorialVoteCard(
                    state = e.tutorialVote.snapshot(), tutorial = GameTutorials.werewolf,
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
                Button(onClick = { server.hostStart() }, enabled = e.canStart) {
                    Text(if (e.canStart) "Start round" else "Need 5+ players")
                }
            }
            WerewolfPhase.NIGHT -> {
                val role = e.players[WerewolfServer.HOST_ID]?.role
                if (role != null) Text("Your role: ${role.displayName} — ${role.tagline}")
                if (role == WerewolfRole.WEREWOLF) {
                    val pack = e.players.values
                        .filter { it.role == WerewolfRole.WEREWOLF && it.id != WerewolfServer.HOST_ID }
                        .joinToString { it.name }
                    if (pack.isNotEmpty()) Text("Pack: $pack",
                        style = MaterialTheme.typography.bodySmall)
                    Text("Pick a villager to kill")
                    for (p in e.alive.filter { it.role != WerewolfRole.WEREWOLF && it.id != WerewolfServer.HOST_ID }) {
                        OutlinedButton(onClick = { server.hostNightAction(p.id) },
                                       modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                    }
                } else if (role == WerewolfRole.SEER) {
                    Text("Pick a player to investigate")
                    for (p in e.alive.filter { it.id != WerewolfServer.HOST_ID }) {
                        OutlinedButton(onClick = { server.hostNightAction(p.id) },
                                       modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                    }
                    val r = e.lastSeerResult
                    if (r != null) {
                        val name = e.players[r.targetId]?.name ?: r.targetId
                        Text("Seer findings: $name is " +
                             if (r.isWerewolf) "a WEREWOLF." else "not a werewolf.")
                    }
                } else {
                    Text("Waiting for wolves and the seer…")
                }
            }
            WerewolfPhase.DAY_REVEAL -> {
                val n = e.lastNight
                Text(if (n?.killedId != null)
                        "${e.players[n.killedId]?.name} was killed by the wolves."
                     else "A quiet night. No one died.")
                for (shot in e.hunterShotsThisRound) {
                    val hn = e.players[shot.hunterId]?.name ?: shot.hunterId
                    val tn = e.players[shot.targetId]?.name ?: shot.targetId
                    Text("$hn took $tn down.")
                }
                Button(onClick = { server.advanceFromReveal() }) { Text("Continue to day vote") }
            }
            WerewolfPhase.DAY_VOTE -> {
                Text("Vote to lynch")
                for (p in e.alive.filter { it.id != WerewolfServer.HOST_ID }) {
                    OutlinedButton(onClick = { server.hostDayVote(p.id) },
                                   modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
                OutlinedButton(onClick = { server.hostDayVote(null) },
                               modifier = Modifier.fillMaxWidth()) { Text("Skip vote") }
            }
            WerewolfPhase.HUNTER_SHOT -> {
                if (e.pendingHunterShooter == WerewolfServer.HOST_ID) {
                    Text("You're the hunter — take one with you")
                    for (p in e.alive.filter { it.id != WerewolfServer.HOST_ID }) {
                        OutlinedButton(onClick = { server.hostHunterShot(p.id) },
                                       modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                    }
                } else {
                    val name = e.pendingHunterShooter?.let { e.players[it]?.name } ?: "the hunter"
                    Text("Waiting for $name to fire…")
                }
            }
            WerewolfPhase.GAME_OVER -> {
                Text(if (e.winner == WerewolfWinner.TOWN) "Village wins" else "Werewolves win",
                     style = MaterialTheme.typography.headlineSmall)
                for (p in e.players.values) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(p.name); Text(p.role?.displayName ?: "—")
                    }
                }
            }
        }
    }
}
