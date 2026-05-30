package com.example.ubapp.games.bureaucrat

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
import com.example.ubapp.theme.Avatar
import com.example.ubapp.theme.MonoLabel
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.UbPrimaryButton
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.theme.ubCard
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native player UI for The Bureaucrat. Consumes the same JSON the
 * `bureaucrat_browser.html` bundle does — keep the two in lockstep.
 */
@Composable
fun BureaucratGuestScreen(ctx: GuestContext) {
    val s = remember { BureaucratGuestState() }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(ctx) {
        ctx.client.onMessage = { msg -> s.handle(msg); tick++ }
        for (m in ctx.replay) s.handle(m)
        onDispose { ctx.client.onMessage = null }
    }
    // Drive the rebuttal countdown.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(s.phase) {
        while (s.phase == "rebuttal") { now = System.currentTimeMillis(); delay(250) }
    }
    @Suppress("UNUSED_EXPRESSION") tick

    val iAmBureaucrat = s.bureaucratId == ctx.yourId
    val secs = ((s.deadlineMs - now) / 1000).coerceAtLeast(0).toInt()

    UbappTheme {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(
                Modifier.verticalScroll(rememberScrollState()).statusBarsPadding()
                    .widthIn(max = 520.dp).fillMaxWidth().padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                when (s.phase) {
                    "lobby"     -> BureaucratLobby(s, ctx)
                    "arguing"   -> BureaucratArguing(s, ctx, iAmBureaucrat)
                    "rebuttal"  -> BureaucratRebuttal(s, ctx, iAmBureaucrat, secs)
                    "roundOver" -> BureaucratRoundOver(s, ctx)
                    "gameOver"  -> BureaucratGameOver(s)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Lobby phase
// ---------------------------------------------------------------------------

@Composable
private fun BureaucratLobby(s: BureaucratGuestState, ctx: GuestContext) {
    // Header
    Text("The Bureaucrat", fontSize = 28.sp, fontWeight = FontWeight.ExtraBold,
        letterSpacing = (-0.8).sp, color = Ub.Foreground)

    TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
        onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
        onVote = { yes ->
            s.myTutorialVote = yes
            ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes))
        })

    // Rules card
    Column(Modifier.fillMaxWidth().ubCard().padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MonoLabel("Rules")
        Text(
            "First to ${s.targetScore} wins · ${s.challengeTokens} loopholes each · " +
            "${s.rebuttalSeconds}s to rebut · ${if (s.aiAssist) "AI rebuttal check on" else "timer only"}",
            fontSize = 13.sp, color = Ub.Muted)
    }

    MonoLabel("In the room · ${s.players.size}")

    for (p in s.players) {
        Row(
            Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Avatar(p.name, host = p.isHost, size = 30.dp)
            Spacer(Modifier.width(12.dp))
            Text(p.name, fontSize = 15.sp,
                fontWeight = if (p.id == ctx.yourId) FontWeight.Bold else FontWeight.SemiBold,
                color = Ub.Foreground)
            if (p.id == ctx.yourId) {
                Spacer(Modifier.width(8.dp))
                MonoLabel("you", size = 9, color = Ub.Accent)
            }
            Spacer(Modifier.weight(1f))
            if (p.isHost) MonoLabel("host", size = 9, color = Ub.Faint)
        }
    }
}

// ---------------------------------------------------------------------------
// Arguing phase
// ---------------------------------------------------------------------------

@Composable
private fun BureaucratArguing(s: BureaucratGuestState, ctx: GuestContext, iAmBureaucrat: Boolean) {
    ArgHeader(s.roundNumber)
    HotSeatBanner(s)
    TaskCard(s.task)
    if (iAmBureaucrat) DenialComposer(ctx)
    else LoopholePanel(s, ctx)
    DenialLedger(s)
    TokenEconomy(s)
    BureaucratScoreboard(s, ctx.yourId)
}

// ---------------------------------------------------------------------------
// Rebuttal phase
// ---------------------------------------------------------------------------

@Composable
private fun BureaucratRebuttal(s: BureaucratGuestState, ctx: GuestContext, iAmBureaucrat: Boolean, secs: Int) {
    ArgHeader(s.roundNumber)
    LiveChallengeBanner(s, secs)
    if (iAmBureaucrat) RebuttalComposer(s, ctx, s.rebuttalMode)
    else SpectateCard(s)
    DenialLedger(s)
}

// ---------------------------------------------------------------------------
// Round-over phase
// ---------------------------------------------------------------------------

@Composable
private fun BureaucratRoundOver(s: BureaucratGuestState, ctx: GuestContext) {
    MonoLabel("End of Round ${s.roundNumber}", color = Ub.Accent)

    // Seat-rotates banner
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Ub.AccentSoft)
            .border(1.dp, Ub.AccentLine, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        BureaucratStamp("NEXT", rotate = -6f)
        val r = s.last
        val nextName = r?.nextBureaucratName ?: ""
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (nextName.isNotEmpty()) {
                Text("$nextName takes the desk next round.", fontSize = 14.sp, color = Ub.Foreground)
                Text(roundOverText(r), fontSize = 13.sp, color = Ub.Muted)
            } else {
                Text(roundOverText(r), fontSize = 14.sp, color = Ub.Foreground)
            }
        }
    }

    StandingsScoreboard(s, ctx.yourId)

    InfoBanner("Waiting for host to start next round…")
}

// ---------------------------------------------------------------------------
// Game-over phase
// ---------------------------------------------------------------------------

@Composable
private fun BureaucratGameOver(s: BureaucratGuestState) {
    // Radial glow at top
    Box(
        Modifier.fillMaxWidth().height(200.dp)
            .background(
                Brush.radialGradient(
                    colors = listOf(Color(0xFFFF2E88).copy(alpha = 0.16f), Color.Transparent),
                    center = Offset(Float.POSITIVE_INFINITY / 2, 0f),
                    radius = 400f
                )
            )
    ) {
        Column(
            Modifier.fillMaxWidth().padding(top = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            BureaucratStamp(
                label = if (s.winnerName.isNotEmpty()) s.winnerName.uppercase() else "WINNER",
                color = Color(0xFF3DDC84),
                rotate = -6f
            )
            Text(
                s.winnerName.ifEmpty { "Someone" },
                fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground
            )
            Text("Wins!", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold,
                color = Color(0xFF3DDC84))
            Text("First past ${s.targetScore} points.", fontSize = 14.sp, color = Ub.Muted)
        }
    }

    StandingsScoreboard(s, "")
}

// ---------------------------------------------------------------------------
// Reusable sub-components
// ---------------------------------------------------------------------------

@Composable
private fun ArgHeader(roundNumber: Int) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        MonoLabel("The Bureaucrat · Round $roundNumber", size = 10, color = Ub.Accent)
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun HotSeatBanner(s: BureaucratGuestState) {
    Row(
        Modifier.fillMaxWidth()
            .ubCard(fill = Ub.Surface, stroke = Ub.AccentLine)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Avatar(name = s.bureaucratName.ifEmpty { "?" }, host = true, size = 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            MonoLabel("In the hot seat", size = 9, color = Ub.Accent)
            Text("${s.bureaucratName.ifEmpty { "Unknown" }} is the Bureaucrat",
                fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("${s.policyLog.count { !it.isRebuttal }}",
                fontSize = 18.sp, fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace, color = Ub.Faint)
            MonoLabel("rulings", size = 8, color = Ub.Faint)
        }
    }
}

@Composable
private fun TaskCard(task: String) {
    Column(
        Modifier.fillMaxWidth()
            .ubCard(radius = Ub.Radius.panel, fill = Ub.AccentSoft, stroke = Ub.AccentLine)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        MonoLabel("The task before the office", color = Ub.Accent)
        Text(task, fontSize = 19.sp, fontWeight = FontWeight.ExtraBold, color = Ub.Foreground)
    }
}

@Composable
private fun DenialComposer(ctx: GuestContext) {
    var draft by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MonoLabel("Issue a ruling")
        Text("Every denial becomes binding policy. Be specific — but specifics can be turned against you.",
            fontSize = 13.sp, color = Ub.Muted)
        OutlinedTextField(value = draft, onValueChange = { if (it.length <= 240) draft = it },
            modifier = Modifier.fillMaxWidth(), minLines = 2,
            placeholder = { Text("e.g. Form 7B is required for all exemptions.") })
        UbPrimaryButton("Stamp and record", enabled = draft.isNotBlank(), onClick = {
            val t = draft.trim()
            if (t.isNotEmpty()) {
                ctx.client.send(JSONObject().put("type", "denial").put("text", t))
                draft = ""
            }
        })
    }
}

@Composable
private fun LoopholePanel(s: BureaucratGuestState, ctx: GuestContext) {
    val left = s.tokens[ctx.yourId] ?: 0
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TokenDots(filled = left, total = s.challengeTokens)
        MonoLabel("Challenge tokens · $left left")
        Text("Argue out loud. When you've trapped the Bureaucrat in their own logic, call a loophole — they must rebut before the clock runs out.",
            fontSize = 13.sp, color = Ub.Muted)
        UbPrimaryButton("Call loophole", enabled = left > 0,
            onClick = { ctx.client.send(JSONObject().put("type", "call_loophole")) })
    }
}

@Composable
private fun DenialLedger(s: BureaucratGuestState) {
    val shortTask = run {
        val words = s.task.split(" ")
        if (words.size > 4) words.take(4).joinToString(" ") + "…" else s.task
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MonoLabel("Denial ledger · this round")
            Spacer(Modifier.weight(1f))
            MonoLabel("Every word is on record", size = 8, color = Ub.Faint)
        }
        if (s.policyLog.isEmpty()) {
            Text("No policy on record yet. The Bureaucrat has said nothing binding… for now.",
                fontSize = 13.sp, color = Ub.Muted)
        } else {
            s.policyLog.forEachIndexed { i, e ->
                LedgerRow(
                    number = i + 1,
                    petition = shortTask,
                    reason = e.text,
                    verdict = if (e.isRebuttal) "REBUTTAL" else "DENIED",
                    isCited = e.isRebuttal
                )
            }
        }
    }
}

@Composable
private fun TokenEconomy(s: BureaucratGuestState) {
    if (s.tokens.isEmpty()) return
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Challenge tokens left")
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            for (p in s.players) {
                val left = s.tokens[p.id] ?: 0
                Column(
                    Modifier.ubCard(radius = Ub.Radius.card).padding(horizontal = 12.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Avatar(p.name, host = p.isHost, size = 26.dp)
                    Text(p.name, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                        color = Ub.Foreground, maxLines = 1)
                    TokenDots(filled = left, total = s.challengeTokens)
                }
            }
        }
    }
}

@Composable
private fun LiveChallengeBanner(s: BureaucratGuestState, secs: Int) {
    Column(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        Color(0xFFFF2E88).copy(alpha = 0.20f),
                        Color(0xFFFF2E88).copy(alpha = 0.05f),
                        Color.Transparent
                    )
                )
            )
            .border(1.dp, Ub.AccentLine, RoundedCornerShape(20.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.Top
        ) {
            TimerRing(seconds = secs, totalSeconds = s.rebuttalSeconds)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                MonoLabel("Challenge · Rebuttal window", size = 9, color = Ub.Accent)
                Text(
                    "${s.challengerName.ifEmpty { "A challenger" }} challenges the ruling",
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground
                )
                val latest = s.policyLog.lastOrNull { !it.isRebuttal }
                if (latest != null) {
                    Text("“${latest.text}”", fontSize = 12.sp, color = Ub.Muted, maxLines = 2)
                }
            }
        }
        val latest = s.policyLog.lastOrNull { !it.isRebuttal }
        if (latest != null) {
            Column(
                Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row, fill = Ub.Surface, stroke = Ub.Line)
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                MonoLabel("Contested ruling", size = 9, color = Ub.Faint)
                Text(latest.text, fontSize = 13.sp, color = Ub.Foreground, maxLines = 3)
            }
        }
    }
}

@Composable
private fun RebuttalComposer(s: BureaucratGuestState, ctx: GuestContext, rebuttalMode: String) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val speechAvailable = remember(context) { SpeechRecognizer.isRecognitionAvailable(context) }
    val isSpeakMode = rebuttalMode == "speak" && speechAvailable
    val fallbackNote = rebuttalMode == "speak" && !speechAvailable
    if (isSpeakMode) {
        RebuttalComposerSpeak(s, ctx)
    } else {
        RebuttalComposerType(s, ctx, fallbackNote)
    }
}

@Composable
private fun RebuttalComposerType(s: BureaucratGuestState, ctx: GuestContext, fallbackNote: Boolean) {
    var draft by remember(s.deadlineMs) { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MonoLabel("Rebuttal demanded")
        Text("${s.challengerName.ifEmpty { "A challenger" }} called a loophole. Defend your policy before the clock runs out.",
            fontSize = 14.sp, color = Ub.Foreground)
        if (fallbackNote) {
            Text("Voice not supported — type instead.", fontSize = 13.sp, color = Ub.Muted)
        }
        OutlinedTextField(value = draft, onValueChange = { if (it.length <= 240) draft = it },
            modifier = Modifier.fillMaxWidth(), minLines = 2,
            placeholder = { Text("Your rebuttal…") })
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                Modifier.size(8.dp).clip(CircleShape)
                    .background(if (s.aiAssist) Color(0xFF3DDC84) else Ub.Muted)
            )
            MonoLabel(
                if (s.aiAssist) "Detector: Listening…" else "Detector: Timer only",
                size = 9,
                color = if (s.aiAssist) Color(0xFF3DDC84) else Ub.Muted
            )
        }
        UbPrimaryButton("Submit rebuttal", enabled = draft.isNotBlank(), onClick = {
            val t = draft.trim()
            if (t.isNotEmpty()) ctx.client.send(JSONObject().put("type", "rebuttal").put("text", t))
        })
    }
}

@Composable
private fun RebuttalComposerSpeak(s: BureaucratGuestState, ctx: GuestContext) {
    var transcript by remember(s.deadlineMs) { mutableStateOf("") }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val matches = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            val best = matches?.firstOrNull()?.trim() ?: ""
            if (best.isNotEmpty()) transcript = best
        }
    }
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MonoLabel("Rebuttal demanded")
        Text("${s.challengerName.ifEmpty { "A challenger" }} called a loophole. Defend your policy before the clock runs out.",
            fontSize = 14.sp, color = Ub.Foreground)
        UbPrimaryButton("🎙 Tap to speak", onClick = {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Say your rebuttal…")
            }
            launcher.launch(intent)
        })
        if (transcript.isNotEmpty()) {
            Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row, fill = Ub.SurfaceHi, stroke = Ub.Line)
                .padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                MonoLabel("Transcript", size = 9, color = Ub.Faint)
                Text(transcript, fontSize = 14.sp, color = Ub.Foreground)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                Modifier.size(8.dp).clip(CircleShape)
                    .background(if (s.aiAssist) Color(0xFF3DDC84) else Ub.Muted)
            )
            MonoLabel(
                if (s.aiAssist) "Detector: Listening…" else "Detector: Timer only",
                size = 9,
                color = if (s.aiAssist) Color(0xFF3DDC84) else Ub.Muted
            )
        }
        UbPrimaryButton("Submit rebuttal", enabled = transcript.isNotBlank(), onClick = {
            val t = transcript.trim()
            if (t.isNotEmpty()) ctx.client.send(JSONObject().put("type", "rebuttal").put("text", t))
        })
    }
}

@Composable
private fun SpectateCard(s: BureaucratGuestState) {
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Loophole called")
        Text("${s.challengerName.ifEmpty { "A challenger" }} is challenging the Bureaucrat.",
            fontSize = 14.sp, color = Ub.Foreground)
        Text("If the Bureaucrat can't rebut in time, the challenger takes the round.",
            fontSize = 13.sp, color = Ub.Faint)
    }
}

@Composable
private fun StandingsScoreboard(s: BureaucratGuestState, myId: String) {
    if (s.scores.isEmpty()) return
    val maxScore = (s.scores.values.maxOrNull() ?: 1).coerceAtLeast(1)
    val sorted = s.scores.entries.sortedByDescending { it.value }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MonoLabel("Standings")
        sorted.forEachIndexed { rankIdx, (id, pts) ->
            val isMe = id == myId
            Row(
                Modifier.fillMaxWidth()
                    .ubCard(radius = Ub.Radius.row,
                        fill = if (isMe) Ub.AccentSoft else Ub.Surface,
                        stroke = if (isMe) Ub.AccentLine else Ub.Line)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text("${rankIdx + 1}", fontSize = 13.sp, fontFamily = FontFamily.Monospace,
                    color = Ub.Faint, modifier = Modifier.width(18.dp))
                Avatar(name = s.nameOf(id), host = false, size = 28.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(s.nameOf(id), fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                            color = Ub.Foreground)
                        if (isMe) Text("· you", fontSize = 13.sp, color = Ub.Accent)
                    }
                    // Score bar
                    BoxWithConstraints(Modifier.fillMaxWidth().height(5.dp)) {
                        val barWidth = maxWidth * (pts.toFloat() / maxScore.toFloat())
                        Box(Modifier.fillMaxSize()
                            .clip(RoundedCornerShape(50))
                            .background(Ub.Line))
                        Box(Modifier.width(barWidth).fillMaxHeight()
                            .clip(RoundedCornerShape(50))
                            .background(Ub.Accent))
                    }
                }
                Column(horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("$pts", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground)
                    MonoLabel("pts", size = 8, color = Ub.Faint)
                }
            }
        }
    }
}

@Composable
private fun BureaucratScoreboard(s: BureaucratGuestState, myId: String) {
    if (s.scores.isEmpty()) return
    val max = s.scores.values.maxOrNull() ?: 0
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MonoLabel("Scores · first to ${s.targetScore}")
        for ((id, pts) in s.scores.entries.sortedByDescending { it.value }) {
            val lead = pts == max && max > 0
            Row(
                Modifier.fillMaxWidth()
                    .ubCard(radius = Ub.Radius.row,
                        fill = if (lead) Ub.AccentSoft else Ub.Surface,
                        stroke = if (lead) Ub.AccentLine else Ub.Line)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(s.nameOf(id) + if (id == myId) " (you)" else "",
                    fontSize = 14.sp, color = Ub.Foreground)
                Spacer(Modifier.weight(1f))
                Text("$pts", fontSize = 14.sp, fontWeight = FontWeight.ExtraBold, color = Ub.Foreground)
            }
        }
    }
}

@Composable
private fun InfoBanner(text: String) {
    Box(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
        .padding(horizontal = 16.dp, vertical = 14.dp)) {
        Text(text, fontSize = 14.sp, color = Ub.Muted)
    }
}

private fun roundOverText(r: BureaucratGuestState.Outcome?): String {
    val who = r?.challengerName?.ifEmpty { "A citizen" } ?: "A citizen"
    return when (r?.reason) {
        "timeout"      -> "$who found the loophole — the Bureaucrat couldn't rebut in time."
        "contradiction" -> "$who won — the rebuttal contradicted the office's own policy."
        "survived"     -> "The Bureaucrat survived the round. No loophole stuck."
        "exhausted"    -> "The citizens ran out of challenges. The Bureaucrat survives."
        else           -> ""
    }
}

// ---------------------------------------------------------------------------
// New shared atoms (private to file)
// ---------------------------------------------------------------------------

/**
 * Rubber-stamp badge — mono bold all-caps text with a matching border,
 * rotated and slightly transparent.
 */
@Composable
private fun BureaucratStamp(
    label: String,
    color: Color = Ub.Accent,
    size: Int = 13,
    rotate: Float = -8f,
) {
    val vPad = (size * 0.32f).dp
    val hPad = (size * 0.7f).dp
    Text(
        label.uppercase(),
        fontFamily = FontFamily.Monospace,
        fontSize = size.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (size * 0.18f).sp,
        color = color,
        modifier = Modifier
            .rotate(rotate)
            .border(2.dp, color, RoundedCornerShape(6.dp))
            .padding(horizontal = hPad, vertical = vPad)
            .graphicsLayer(alpha = 0.92f),
    )
}

/**
 * Square bureaucrat glyph icon — surfaceHi tile with a rotated document
 * outline and a solid accent bar inside.
 */
@Composable
fun GlyphBureaucrat(size: Dp = 64.dp) {
    Box(
        Modifier
            .size(size)
            .clip(RoundedCornerShape((size.value * 0.18f).dp))
            .background(Ub.SurfaceHi),
        contentAlignment = Alignment.Center
    ) {
        val rectW = size * 0.62f
        val rectH = size * 0.42f
        val strokeW = (size.value * 0.045f).coerceAtLeast(2f).dp
        Box(Modifier.rotate(-9f)) {
            Box(
                Modifier
                    .size(rectW, rectH)
                    .border(strokeW, Ub.Accent, RoundedCornerShape((size.value * 0.06f).dp)),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    Modifier
                        .width(rectW * 0.64f)
                        .height((rectH.value * 0.175f).coerceAtLeast(2f).dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(Ub.Accent)
                )
            }
        }
    }
}

/**
 * Ledger entry row — numbered petition with a verdict pill.
 */
@Composable
private fun LedgerRow(
    number: Int,
    petition: String,
    reason: String,
    verdict: String = "DENIED",
    isCited: Boolean = false,
) {
    val verdictColor = when (verdict) {
        "APPROVED" -> Color(0xFF3DDC84)
        "DENIED"   -> Ub.Accent
        else       -> Ub.Muted
    }
    Row(
        Modifier.fillMaxWidth()
            .ubCard(
                radius = 12.dp,
                fill = if (isCited) Ub.AccentSoft else Color.White.copy(alpha = 0.03f),
                stroke = if (isCited) Ub.AccentLine else Ub.Line
            )
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            "#$number",
            fontFamily = FontFamily.Monospace,
            fontSize = 9.sp,
            fontWeight = FontWeight.Medium,
            color = Ub.Faint,
            modifier = Modifier.width(30.dp)
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(petition, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground)
            Text("“$reason”", fontSize = 11.sp, color = Ub.Muted, maxLines = 2)
        }
        Text(
            verdict,
            fontFamily = FontFamily.Monospace,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold,
            color = verdictColor,
            modifier = Modifier
                .border(1.dp, verdictColor, RoundedCornerShape(5.dp))
                .padding(horizontal = 7.dp, vertical = 3.dp)
        )
    }
}

/**
 * Circular countdown ring — track + progress arc + center label.
 */
@Composable
private fun TimerRing(seconds: Int, totalSeconds: Int) {
    val progress = if (totalSeconds > 0) seconds.toFloat() / totalSeconds.toFloat() else 0f
    Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(64.dp)) {
            val strokePx = 4.dp.toPx()
            val inset = strokePx / 2
            val arcSize = Size(size.width - strokePx, size.height - strokePx)
            // Track
            drawArc(
                color = Ub.LineStrong,
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = arcSize,
                style = Stroke(width = strokePx, cap = StrokeCap.Round)
            )
            // Progress arc
            drawArc(
                color = Ub.Accent,
                startAngle = -90f,
                sweepAngle = 360f * progress,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = arcSize,
                style = Stroke(width = strokePx, cap = StrokeCap.Round)
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text("$seconds", fontSize = 22.sp, fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace, color = Ub.Foreground)
            Text("SEC", fontSize = 8.sp, fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium, letterSpacing = 1.2.sp, color = Ub.Muted)
        }
    }
}

/**
 * Row of filled/empty dots representing token count.
 */
@Composable
private fun TokenDots(filled: Int, total: Int, gap: Dp = 3.dp) {
    Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
        repeat(total.coerceAtLeast(0)) { i ->
            Box(
                Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(if (i < filled) Ub.Accent else Color.White.copy(alpha = 0.14f))
                    .then(
                        if (i >= filled)
                            Modifier.border(0.5.dp, Ub.Line, CircleShape)
                        else Modifier
                    )
            )
        }
    }
}

// ---------------------------------------------------------------------------
// BureaucratGuestState (unchanged)
// ---------------------------------------------------------------------------

class BureaucratGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean)
    data class Entry(val text: String, val isRebuttal: Boolean, val challengerId: String?)
    data class Outcome(val reason: String, val challengerName: String, val nextBureaucratName: String)

    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var roundNumber by mutableIntStateOf(0)
    var bureaucratId by mutableStateOf<String?>(null)
    var bureaucratName by mutableStateOf("")
    var task by mutableStateOf("")
    var targetScore by mutableIntStateOf(10)
    var challengeTokens by mutableIntStateOf(2)
    var rebuttalSeconds by mutableIntStateOf(20)
    var aiAssist by mutableStateOf(true)
    var rebuttalMode by mutableStateOf("type")
    var scores by mutableStateOf<Map<String, Int>>(emptyMap())
    var tokens by mutableStateOf<Map<String, Int>>(emptyMap())
    var policyLog by mutableStateOf<List<Entry>>(emptyList())
    var challengerId by mutableStateOf<String?>(null)
    var challengerName by mutableStateOf("")
    var deadlineMs by mutableLongStateOf(0L)
    var last by mutableStateOf<Outcome?>(null)
    var winnerName by mutableStateOf("")
    var tutorialState by mutableStateOf(GuestTutorialState())
    var tutorialContent by mutableStateOf<GuestTutorialContent?>(null)
    var myTutorialVote by mutableStateOf<Boolean?>(null)

    fun nameOf(id: String): String = players.firstOrNull { it.id == id }?.name ?: id

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
            "lobby" -> {
                val arr = m.optJSONArray("players")
                players = if (arr == null) emptyList() else (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"), o.optBoolean("isHost"))
                }
                phase = "lobby"
            }
            "options" -> {
                targetScore = m.optInt("targetScore", targetScore)
                challengeTokens = m.optInt("challengeTokens", challengeTokens)
                rebuttalSeconds = m.optInt("rebuttalSeconds", rebuttalSeconds)
                aiAssist = m.optBoolean("aiAssist", aiAssist)
                rebuttalMode = m.optString("rebuttalMode", "type").let { if (it == "speak") "speak" else "type" }
            }
            "round", "policy" -> applyRound(m)
            "rebuttal_open" -> {
                phase = "rebuttal"
                challengerId = if (m.isNull("challengerId")) null else m.optString("challengerId")
                challengerName = m.optString("challengerName")
                deadlineMs = m.optLong("deadlineMs", 0L)
                rebuttalSeconds = m.optInt("seconds", rebuttalSeconds)
                m.optJSONArray("policyLog")?.let { policyLog = readLog(it) }
            }
            "round_over" -> {
                phase = "roundOver"
                last = Outcome(m.optString("reason"), m.optString("challengerName"),
                    if (m.isNull("nextBureaucratId")) "" else nameOf(m.optString("nextBureaucratId")))
                scores = readScores(m.optJSONObject("scores"))
                targetScore = m.optInt("targetScore", targetScore)
                m.optJSONArray("policyLog")?.let { policyLog = readLog(it) }
            }
            "game_over" -> {
                phase = "gameOver"
                winnerName = m.optString("winnerName")
                scores = readScores(m.optJSONObject("scores"))
            }
            "tutorial_vote_state" -> {
                tutorialState = GuestTutorialState.from(m)
                if (m.has("title")) tutorialContent = GuestTutorialContent(
                    m.optString("title"),
                    GuestTutorialContent.readSections(m.optJSONArray("sections")),
                    GuestTutorialContent.readSections(m.optJSONArray("menuSections")))
            }
        }
    }

    private fun applyRound(m: JSONObject) {
        phase = if (m.optString("phase") == "rebuttal") "rebuttal" else "arguing"
        roundNumber = m.optInt("roundNumber", roundNumber)
        bureaucratId = if (m.isNull("bureaucratId")) null else m.optString("bureaucratId")
        bureaucratName = if (m.isNull("bureaucratName")) "" else m.optString("bureaucratName")
        task = if (m.isNull("task")) "" else m.optString("task")
        targetScore = m.optInt("targetScore", targetScore)
        scores = readScores(m.optJSONObject("scores"))
        tokens = readScores(m.optJSONObject("tokens"))
        policyLog = readLog(m.optJSONArray("policyLog"))
    }

    private fun readLog(arr: JSONArray?): List<Entry> {
        if (arr == null) return emptyList()
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            Entry(o.optString("text"), o.optBoolean("isRebuttal"),
                if (o.isNull("challengerId")) null else o.optString("challengerId"))
        }
    }
    private fun readScores(o: JSONObject?): Map<String, Int> {
        if (o == null) return emptyMap()
        val map = LinkedHashMap<String, Int>()
        o.keys().forEach { map[it] = o.optInt(it) }
        return map
    }
}
