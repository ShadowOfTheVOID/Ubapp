package com.example.ubapp.games.bureaucrat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
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
                    "lobby" -> Lobby(s, ctx)
                    "arguing" -> {
                        Header("Round ${s.roundNumber}")
                        RoleBar(iAmBureaucrat, s.bureaucratName)
                        TaskCard(s.task)
                        if (iAmBureaucrat) DenialComposer(ctx)
                        else LoopholePanel(s, ctx)
                        PolicyLog(s)
                        Scoreboard(s, ctx.yourId)
                    }
                    "rebuttal" -> {
                        Header("Loophole!")
                        RoleBar(iAmBureaucrat, s.bureaucratName)
                        TaskCard(s.task)
                        if (iAmBureaucrat) RebuttalComposer(s, secs, ctx)
                        else SpectateRebuttal(s, secs)
                        PolicyLog(s)
                    }
                    "roundOver" -> {
                        Header("Round over")
                        RoundOverCard(s)
                        Scoreboard(s, ctx.yourId)
                        InfoBanner("Waiting for the host to start the next round…")
                    }
                    "gameOver" -> {
                        Header("${s.winnerName.ifEmpty { "Someone" }} wins!")
                        InfoBanner("First past ${s.targetScore} points. The office is finally closed.")
                        Scoreboard(s, ctx.yourId)
                    }
                }
            }
        }
    }
}

@Composable private fun Header(t: String) {
    Text(t, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.8).sp, color = Ub.Foreground)
}

@Composable private fun Lobby(s: BureaucratGuestState, ctx: GuestContext) {
    Header("The Bureaucrat")
    TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
        onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
        onVote = { yes -> s.myTutorialVote = yes
            ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MonoLabel("Rules")
        Text("First to ${s.targetScore} wins · ${s.challengeTokens} loopholes each · ${s.rebuttalSeconds}s to rebut · ${if (s.aiAssist) "AI rebuttal check on" else "timer only"}",
            fontSize = 13.sp, color = Ub.Muted)
    }
    MonoLabel("Players · ${s.players.size}")
    for (p in s.players) Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
        .padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(p.name, fontSize = 15.sp,
            fontWeight = if (p.id == ctx.yourId) FontWeight.Bold else FontWeight.SemiBold, color = Ub.Foreground)
        if (p.id == ctx.yourId) { Spacer(Modifier.width(8.dp)); MonoLabel("you", size = 9, color = Ub.Accent) }
        Spacer(Modifier.weight(1f))
        if (p.isHost) MonoLabel("host", size = 9, color = Ub.Faint)
    }
}

@Composable private fun RoleBar(bureaucrat: Boolean, bureaucratName: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.clip(RoundedCornerShape(50))
            .background(if (bureaucrat) Ub.Accent else Color.White.copy(alpha = 0.08f))
            .padding(horizontal = 10.dp, vertical = 4.dp)) {
            MonoLabel(if (bureaucrat) "You are the Bureaucrat" else "Citizen", size = 9,
                color = if (bureaucrat) Ub.OnAccent else Ub.Foreground)
        }
        if (!bureaucrat && bureaucratName.isNotEmpty())
            Text("Bureaucrat: $bureaucratName", fontSize = 13.sp, color = Ub.Muted)
    }
}

@Composable private fun TaskCard(task: String) {
    Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel, fill = Ub.AccentSoft, stroke = Ub.AccentLine)
        .padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("The task before the office", color = Ub.Accent)
        Text(task, fontSize = 19.sp, fontWeight = FontWeight.ExtraBold, color = Ub.Foreground)
    }
}

@Composable private fun DenialComposer(ctx: GuestContext) {
    var draft by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MonoLabel("Issue a denial")
        Text("Every denial becomes binding policy. Be specific — but specifics can be turned against you.",
            fontSize = 13.sp, color = Ub.Muted)
        OutlinedTextField(value = draft, onValueChange = { if (it.length <= 240) draft = it },
            modifier = Modifier.fillMaxWidth(), minLines = 2,
            placeholder = { Text("e.g. Form 7B is required for all exemptions.") })
        UbPrimaryButton("Add to policy log", enabled = draft.isNotBlank(), onClick = {
            val t = draft.trim(); if (t.isNotEmpty()) { ctx.client.send(JSONObject().put("type", "denial").put("text", t)); draft = "" }
        })
    }
}

@Composable private fun LoopholePanel(s: BureaucratGuestState, ctx: GuestContext) {
    val left = s.tokens[ctx.yourId] ?: 0
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MonoLabel("Find the loophole")
        Text("Argue out loud. When you've trapped the Bureaucrat in their own logic, call a loophole — they must rebut before the clock runs out.",
            fontSize = 13.sp, color = Ub.Muted)
        UbPrimaryButton("Call loophole ($left left)", enabled = left > 0,
            onClick = { ctx.client.send(JSONObject().put("type", "call_loophole")) })
        if (left <= 0) Text("You're out of challenges this round.", fontSize = 13.sp, color = Ub.Faint)
    }
}

@Composable private fun RebuttalComposer(s: BureaucratGuestState, secs: Int, ctx: GuestContext) {
    var draft by remember(s.deadlineMs) { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MonoLabel("Rebuttal demanded")
        Text("${s.challengerName} called a loophole. Defend your policy before the clock runs out.",
            fontSize = 14.sp, color = Ub.Foreground)
        Countdown(secs)
        OutlinedTextField(value = draft, onValueChange = { if (it.length <= 240) draft = it },
            modifier = Modifier.fillMaxWidth(), minLines = 2,
            placeholder = { Text("Your binding rebuttal…") })
        UbPrimaryButton("Submit rebuttal", enabled = draft.isNotBlank(), onClick = {
            val t = draft.trim(); if (t.isNotEmpty()) ctx.client.send(JSONObject().put("type", "rebuttal").put("text", t))
        })
    }
}

@Composable private fun SpectateRebuttal(s: BureaucratGuestState, secs: Int) {
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Loophole called")
        Text("${s.challengerName} is challenging the Bureaucrat.", fontSize = 14.sp, color = Ub.Foreground)
        Countdown(secs)
        Text("If the Bureaucrat can't rebut in time, ${s.challengerName} takes the round.",
            fontSize = 13.sp, color = Ub.Muted)
    }
}

@Composable private fun Countdown(secs: Int) {
    Text("${secs}s", fontSize = 46.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1).sp,
        color = if (secs <= 5) Ub.Accent else Ub.Foreground)
}

@Composable private fun PolicyLog(s: BureaucratGuestState) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        MonoLabel("Policy log")
        if (s.policyLog.isEmpty())
            Text("No policy on record yet. The Bureaucrat has said nothing binding… for now.",
                fontSize = 13.sp, color = Ub.Muted)
        else s.policyLog.forEachIndexed { i, e ->
            Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row,
                fill = if (e.isRebuttal) Ub.AccentSoft else Ub.Surface,
                stroke = if (e.isRebuttal) Ub.AccentLine else Ub.Line)
                .padding(horizontal = 14.dp, vertical = 12.dp)) {
                MonoLabel(if (e.isRebuttal) "rebuttal" else "policy §${i + 1}", size = 9, color = Ub.Faint)
                Spacer(Modifier.height(4.dp))
                Text(e.text, fontSize = 14.sp, color = Ub.Foreground)
            }
        }
    }
}

@Composable private fun RoundOverCard(s: BureaucratGuestState) {
    val r = s.last
    val text = when (r?.reason) {
        "timeout" -> "${r.challengerName.ifEmpty { "A citizen" }} found the loophole — the Bureaucrat couldn't rebut in time."
        "contradiction" -> "${r.challengerName.ifEmpty { "A citizen" }} won — the rebuttal contradicted the office's own policy."
        "survived" -> "The Bureaucrat survived the round. No loophole stuck."
        "exhausted" -> "The citizens ran out of challenges. The Bureaucrat survives."
        else -> ""
    }
    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text, fontSize = 14.sp, color = Ub.Foreground)
        val nextName = r?.nextBureaucratName ?: ""
        if (nextName.isNotEmpty()) Text("Next round, $nextName takes the desk.", fontSize = 13.sp, color = Ub.Muted)
    }
}

@Composable private fun Scoreboard(s: BureaucratGuestState, myId: String) {
    if (s.scores.isEmpty()) return
    val max = s.scores.values.maxOrNull() ?: 0
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MonoLabel("Scores · first to ${s.targetScore}")
        for ((id, pts) in s.scores.entries.sortedByDescending { it.value }) {
            val lead = pts == max && max > 0
            Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row,
                fill = if (lead) Ub.AccentSoft else Ub.Surface, stroke = if (lead) Ub.AccentLine else Ub.Line)
                .padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(s.nameOf(id) + if (id == myId) " (you)" else "", fontSize = 14.sp, color = Ub.Foreground)
                Spacer(Modifier.weight(1f))
                Text("$pts", fontSize = 14.sp, fontWeight = FontWeight.ExtraBold, color = Ub.Foreground)
            }
        }
    }
}

@Composable private fun InfoBanner(text: String) {
    Box(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row).padding(horizontal = 16.dp, vertical = 14.dp)) {
        Text(text, fontSize = 14.sp, color = Ub.Muted)
    }
}

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
                    val o = arr.getJSONObject(it); Player(o.optString("id"), o.optString("name"), o.optBoolean("isHost"))
                }
                phase = "lobby"
            }
            "options" -> {
                targetScore = m.optInt("targetScore", targetScore)
                challengeTokens = m.optInt("challengeTokens", challengeTokens)
                rebuttalSeconds = m.optInt("rebuttalSeconds", rebuttalSeconds)
                aiAssist = m.optBoolean("aiAssist", aiAssist)
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
