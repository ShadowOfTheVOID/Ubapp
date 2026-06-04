package com.example.jamboree.games.bureaucrat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.join.GuestContext
import com.example.jamboree.settings.AppSettings
import com.example.jamboree.shared.HostingChrome
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.theme.ubCard
import com.example.jamboree.tutorials.GameTutorials
import com.example.jamboree.tutorials.TutorialVoteCard
import com.example.jamboree.tutorials.snapshot

/**
 * Host screen for The Bureaucrat. The lobby is host-owned (QR, options, Start);
 * once a round begins the host plays on the *same* player screen every guest
 * sees ([BureaucratGuestScreen]) via an in-process loopback, plus a control bar
 * for the two orchestration steps the player screen lacks: calling a round for
 * the Bureaucrat and advancing to the next round.
 */
@Composable
fun BureaucratScreen() {
    val ctx = LocalContext.current
    val server = remember { BureaucratServer(ctx, AppSettings.hostName(ctx)) }
    val loopback = remember { server.makeLoopback() }
    val loopCtx = remember {
        GuestContext(loopback, "bureaucrat", BureaucratServer.HOST_ID, server.hostName, emptyList())
    }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        server.onStopped = { joinUrl = null }
        onDispose { server.stop() }
    }
    val engine = server.engine
    @Suppress("UNUSED_EXPRESSION") tick

    JamboreeTheme {
        if (engine.phase == BureaucratPhase.LOBBY) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    Modifier.verticalScroll(rememberScrollState()).statusBarsPadding()
                        .widthIn(max = 520.dp).fillMaxWidth().padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    // Updated lobby header with GlyphBureaucrat
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        GlyphBureaucrat(size = 56.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            MonoLabel("Hosting · The Bureaucrat", color = Ub.Accent)
                            Text("Waiting for players", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold,
                                letterSpacing = (-0.6).sp, color = Ub.Foreground)
                        }
                    }
                    HostingChrome(joinUrl = joinUrl,
                        onStart = { joinUrl = server.start() },
                        onStop = { server.stop(); joinUrl = null })
                    TutorialVoteCard(
                        state = engine.tutorialVote.snapshot(),
                        tutorial = GameTutorials.bureaucrat,
                        onCall = server::hostCallTutorialVote,
                        onVote = server::hostTutorialVote,
                        onDismiss = server::hostDismissTutorial,
                    )
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MonoLabel("Players · ${engine.players.size}")
                        for (p in engine.players.values) {
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
                    OptionsCard(engine, server)
                    if (engine.canStart) {
                        UbPrimaryButton("Start game · ${engine.players.size} players", onClick = { server.hostStart() })
                    } else {
                        Text("Need at least 3 players to start.", fontSize = 13.sp, color = Ub.Muted)
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { BureaucratGuestScreen(loopCtx) }
                when (engine.phase) {
                    BureaucratPhase.ARGUING ->
                        UbPrimaryButton("Bureaucrat survives the round",
                            modifier = Modifier.fillMaxWidth().padding(20.dp),
                            onClick = { server.hostSurvive() })
                    BureaucratPhase.ROUND_OVER ->
                        UbPrimaryButton("Next round",
                            modifier = Modifier.fillMaxWidth().padding(20.dp),
                            onClick = { server.hostNextRound() })
                    else -> {}
                }
            }
        }
    }
}

@Composable
private fun OptionsCard(engine: BureaucratEngine, server: BureaucratServer) {
    val o = engine.options
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Options")
        Column(Modifier.fillMaxWidth().ubCard().padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Stepper("Target score", o.targetScore, 3, 50, step = 1) {
                server.hostSetOptions(o.copy(targetScore = it))
            }
            Stepper("Loopholes each", o.challengeTokens, 1, 9, step = 1) {
                server.hostSetOptions(o.copy(challengeTokens = it))
            }
            Stepper("Rebuttal seconds", o.rebuttalSeconds, 5, 120, step = 5) {
                server.hostSetOptions(o.copy(rebuttalSeconds = it))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = o.aiAssist, onCheckedChange = { server.hostSetOptions(o.copy(aiAssist = it)) })
                Text("  AI rebuttal check (falls back to timer)")
            }
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Rebuttal mode:", Modifier.weight(1f))
                SingleChoiceSegmentedButtonRow {
                    SegmentedButton(
                        selected = o.rebuttalMode == "type",
                        onClick = { server.hostSetOptions(o.copy(rebuttalMode = "type")) },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                        label = { Text("Type") }
                    )
                    SegmentedButton(
                        selected = o.rebuttalMode == "speak",
                        onClick = { server.hostSetOptions(o.copy(rebuttalMode = "speak")) },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                        label = { Text("Speak") }
                    )
                }
            }
        }
    }
}

@Composable
private fun Stepper(label: String, value: Int, min: Int, max: Int, step: Int, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("$label: $value", Modifier.weight(1f))
        IconButton(onClick = { onChange((value - step).coerceAtLeast(min)) }, enabled = value > min) {
            Text("−", style = MaterialTheme.typography.titleLarge)
        }
        IconButton(onClick = { onChange((value + step).coerceAtMost(max)) }, enabled = value < max) {
            Text("+", style = MaterialTheme.typography.titleLarge)
        }
    }
}
