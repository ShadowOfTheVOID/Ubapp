package com.example.ubapp.games.secrethitler

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.tutorials.GameTutorials
import com.example.ubapp.tutorials.TutorialVoteCard
import com.example.ubapp.tutorials.snapshot

@Composable
fun SecretHitlerScreen() {
    val ctx = LocalContext.current
    val server = remember { SecretHitlerServer(ctx) }
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
        HostingChrome(joinUrl) { joinUrl = server.start() }

        if (engine.phase == SecretHitlerPhase.LOBBY) {
            TutorialVoteCard(
                state = engine.tutorialVote.snapshot(),
                tutorial = GameTutorials.secretHitler,
                onCall = server::hostCallTutorialVote,
                onVote = server::hostTutorialVote,
                onDismiss = server::hostDismissTutorial,
            )
            LobbySection(engine, onStart = { server.hostStart() })
        } else {
            TracksRow(engine)
            RoleCard(engine)
            GovernmentRow(engine)
            PhaseSection(engine, server)
        }
    }
}

@Composable
private fun LobbySection(engine: SecretHitlerEngine, onStart: () -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text("Players (${engine.players.size})", style = MaterialTheme.typography.titleSmall)
            for (id in engine.seatOrder) {
                val p = engine.players[id] ?: continue
                Text(p.name + if (p.isHost) " (host)" else "")
            }
        }
    }
    Button(onClick = onStart, enabled = engine.canStart) {
        Text(if (engine.canStart) "Start round" else "Need 5–10 players")
    }
}

@Composable
private fun TracksRow(engine: SecretHitlerEngine) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TrackCell("Liberal", "${engine.liberalPolicies} / 5", Color(0xFF2D6CDF))
        TrackCell("Fascist", "${engine.fascistPolicies} / 6", Color(0xFFC2410C))
        TrackCell("Election", "${engine.electionTracker} / 3", MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun RowScope.TrackCell(label: String, value: String, color: Color) {
    ElevatedCard(Modifier.weight(1f)) {
        Column(Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelSmall)
            Text(value, style = MaterialTheme.typography.titleMedium, color = color)
        }
    }
}

@Composable
private fun RoleCard(engine: SecretHitlerEngine) {
    val role = engine.players[SecretHitlerServer.HOST_ID]?.role ?: return
    val tagline = when (role) {
        SecretHitlerRole.LIBERAL -> "Pass 5 Liberal policies, or have Hitler executed."
        SecretHitlerRole.FASCIST -> "Get 6 Fascist policies through — or sneak Hitler in as Chancellor after 3."
        SecretHitlerRole.HITLER -> "Stay hidden. After 3 Fascist policies, getting elected Chancellor wins the game."
    }
    val allies = engine.knownAllies(SecretHitlerServer.HOST_ID)
        .mapNotNull { engine.players[it]?.name }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text("Your role: ${role.name.lowercase().replaceFirstChar { it.uppercase() }}",
                 style = MaterialTheme.typography.titleSmall)
            Text(tagline, style = MaterialTheme.typography.bodyMedium)
            if (allies.isNotEmpty()) {
                Text("Allies: ${allies.joinToString(", ")}",
                     style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun GovernmentRow(engine: SecretHitlerEngine) {
    val pres = engine.presidentId?.let { engine.players[it]?.name } ?: "—"
    val chanId = engine.chancellorId ?: engine.chancellorNomineeId
    val chan = chanId?.let { engine.players[it]?.name } ?: "—"
    ElevatedCard(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Column { Text("President", style = MaterialTheme.typography.labelSmall); Text(pres) }
            Column { Text("Chancellor", style = MaterialTheme.typography.labelSmall); Text(chan) }
        }
    }
}

@Composable
private fun PhaseSection(engine: SecretHitlerEngine, server: SecretHitlerServer) {
    val amPresident = engine.presidentId == SecretHitlerServer.HOST_ID
    val amChancellor = engine.chancellorId == SecretHitlerServer.HOST_ID
    val hostAlive = engine.players[SecretHitlerServer.HOST_ID]?.alive == true

    when (engine.phase) {
        SecretHitlerPhase.NOMINATION -> {
            if (amPresident) {
                Text("Nominate a Chancellor", style = MaterialTheme.typography.titleSmall)
                for (p in engine.eligibleChancellorNominees()) {
                    OutlinedButton(
                        onClick = { server.hostNominate(p.id) },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(p.name) }
                }
            } else Text("Waiting for ${engine.players[engine.presidentId]?.name ?: "—"} to nominate…")
        }
        SecretHitlerPhase.ELECTION -> {
            Text("Vote on the government", style = MaterialTheme.typography.titleSmall)
            Text("${engine.electionVotes.size} / ${engine.alive.size} voted",
                 style = MaterialTheme.typography.bodySmall)
            if (hostAlive) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { server.hostVote(true) }, modifier = Modifier.weight(1f),
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)))
                { Text("Ja!") }
                Button(onClick = { server.hostVote(false) }, modifier = Modifier.weight(1f),
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828)))
                { Text("Nein!") }
            }
        }
        SecretHitlerPhase.PRESIDENT_DISCARD -> {
            if (amPresident) {
                Text("Discard one — remaining two go to the Chancellor",
                     style = MaterialTheme.typography.titleSmall)
                engine.presidentialHand.forEachIndexed { i, pol ->
                    OutlinedButton(onClick = { server.hostDiscard(i) },
                                   modifier = Modifier.fillMaxWidth())
                    { Text("Discard ${policyLabel(pol)}") }
                }
            } else Text("Waiting for the President to discard…")
        }
        SecretHitlerPhase.CHANCELLOR_ENACT -> {
            if (amChancellor) {
                Text("Enact one policy", style = MaterialTheme.typography.titleSmall)
                engine.chancellorHand.forEachIndexed { i, pol ->
                    OutlinedButton(onClick = { server.hostEnact(i) },
                                   modifier = Modifier.fillMaxWidth())
                    { Text("Enact ${policyLabel(pol)}") }
                }
                if (engine.vetoUnlocked) {
                    TextButton(onClick = { server.hostRequestVeto() }) { Text("Request veto") }
                }
            } else Text("Waiting for the Chancellor to enact…")
        }
        SecretHitlerPhase.VETO_DECISION -> {
            if (amPresident) {
                Text("Chancellor wants to veto", style = MaterialTheme.typography.titleSmall)
                Text("If you agree, both policies are discarded and the tracker advances.",
                     style = MaterialTheme.typography.bodySmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { server.hostVetoResponse(true) }, modifier = Modifier.weight(1f))
                    { Text("Agree — veto") }
                    OutlinedButton(onClick = { server.hostVetoResponse(false) }, modifier = Modifier.weight(1f))
                    { Text("Refuse") }
                }
            } else Text("Veto requested — waiting for the President…")
        }
        SecretHitlerPhase.POLICY_PEEK -> {
            if (amPresident) {
                Text("Top three policies", style = MaterialTheme.typography.titleSmall)
                engine.peekedPolicies.forEachIndexed { i, pol ->
                    Text("${i + 1}. ${policyLabel(pol)}")
                }
                Button(onClick = { server.hostAcknowledgePeek() }) { Text("Done") }
            } else Text("The President is peeking at the deck…")
        }
        SecretHitlerPhase.INVESTIGATION -> {
            if (amPresident) {
                Text("Investigate a player's party", style = MaterialTheme.typography.titleSmall)
                for (p in engine.investigationTargets()) {
                    OutlinedButton(onClick = { server.hostInvestigate(p.id) },
                                   modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
            } else Text("The President is investigating someone…")
        }
        SecretHitlerPhase.INVESTIGATION_REVEAL -> {
            val inv = engine.lastInvestigation
            if (amPresident && inv != null) {
                val name = engine.players[inv.subjectId]?.name ?: inv.subjectId
                val party = inv.party.name.lowercase().replaceFirstChar { it.uppercase() }
                Text("$name is part of the $party party",
                     style = MaterialTheme.typography.titleSmall)
                Text("This is your call — share it truthfully, or lie.",
                     style = MaterialTheme.typography.bodySmall)
                Button(onClick = { server.hostAcknowledgeInvestigation() }) { Text("Done") }
            } else Text("The President has the investigation result…")
        }
        SecretHitlerPhase.SPECIAL_ELECTION -> {
            if (amPresident) {
                Text("Pick the next President", style = MaterialTheme.typography.titleSmall)
                for (p in engine.alive.filter { it.id != engine.presidentId }) {
                    OutlinedButton(onClick = { server.hostSpecialElection(p.id) },
                                   modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
            } else Text("The President is calling a special election…")
        }
        SecretHitlerPhase.EXECUTION -> {
            if (amPresident) {
                Text("Execute a player", style = MaterialTheme.typography.titleSmall)
                for (p in engine.executionTargets()) {
                    OutlinedButton(onClick = { server.hostExecute(p.id) },
                                   modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
            } else Text("The President is choosing someone to execute…")
        }
        SecretHitlerPhase.GAME_OVER -> {
            val win = if (engine.winner == SecretHitlerWinner.LIBERAL) "Liberals win" else "Fascists win"
            val reason = when (engine.winReason) {
                SecretHitlerWinReason.FIVE_LIBERAL_POLICIES -> "Five Liberal policies enacted."
                SecretHitlerWinReason.SIX_FASCIST_POLICIES -> "Six Fascist policies enacted."
                SecretHitlerWinReason.HITLER_ELECTED_CHANCELLOR -> "Hitler was elected Chancellor."
                SecretHitlerWinReason.HITLER_EXECUTED -> "Hitler was executed."
                null -> ""
            }
            Text(win, style = MaterialTheme.typography.headlineSmall)
            Text(reason, style = MaterialTheme.typography.bodyMedium)
            for (id in engine.seatOrder) {
                val p = engine.players[id] ?: continue
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(p.name)
                    Text(p.role?.name?.lowercase()?.replaceFirstChar { it.uppercase() } ?: "—")
                }
            }
        }
        SecretHitlerPhase.LOBBY -> Unit
    }
}

private fun policyLabel(p: SecretHitlerPolicy): String =
    if (p == SecretHitlerPolicy.LIBERAL) "Liberal policy" else "Fascist policy"
