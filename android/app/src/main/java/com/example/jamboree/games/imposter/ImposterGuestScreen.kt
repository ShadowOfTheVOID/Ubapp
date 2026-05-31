package com.example.jamboree.games.imposter

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import com.example.jamboree.ads.AdBanner
import com.example.jamboree.ads.AdBannerPlacement
import com.example.jamboree.ads.AdInterstitialController
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.LobbyPlayerRow
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.theme.ubCard
import com.example.jamboree.join.GuestContext
import com.example.jamboree.join.GuestSeriesState
import com.example.jamboree.join.GuestTutorialContent
import com.example.jamboree.join.GuestTutorialState
import com.example.jamboree.join.SeriesBannerCard
import com.example.jamboree.join.TutorialGuestCard
import org.json.JSONObject

@Composable
fun ImposterGuestScreen(ctx: GuestContext) {
    val s = remember { ImposterGuestState() }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(ctx) {
        ctx.client.onMessage = { msg -> s.handle(msg); tick++ }
        for (m in ctx.replay) s.handle(m)
        onDispose { ctx.client.onMessage = null }
    }
    @Suppress("UNUSED_EXPRESSION") tick
    var showInterstitial by remember { mutableStateOf(false) }
    var interstitialFired by remember { mutableStateOf(false) }
    val gameOverPhase = "result"
    LaunchedEffect(tick) {
        if (s.phase == gameOverPhase && !interstitialFired) {
            interstitialFired = true
            showInterstitial = true
        }
    }

    JamboreeTheme {
    Box(Modifier.fillMaxSize()) {
    Column(Modifier.fillMaxSize()) {
    Box(Modifier.weight(1f), contentAlignment = Alignment.TopCenter) {
    Column(
        Modifier
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .widthIn(max = 520.dp)
            .fillMaxWidth()
            .padding(20.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        MonoLabel(phaseLabel(s), color = Ub.Accent)
        if (s.error != null) InfoBanner(s.error!!, accent = true)
        SeriesBannerCard(s.series)
        when (s.phase) {
            "lobby" -> {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Waiting for the host", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
                         letterSpacing = (-0.8).sp, color = Ub.Foreground)
                    Text("Playing as ${ctx.yourName}", fontSize = 13.sp, color = Ub.Muted)
                }
                TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                    onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                    onVote = { yes -> s.myTutorialVote = yes
                        ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                MonoLabel("In the room · ${s.players.size}")
                for (p in s.players) LobbyPlayerRow(p.name, p.isHost)
            }
            "playing" -> {
                if (s.isImposter) {
                    Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel,
                            fill = Ub.AccentSoft, stroke = Ub.AccentLine).padding(20.dp),
                           verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MonoLabel("Your secret role", color = Ub.Accent)
                        Text("You are the Imposter.", fontSize = 32.sp, fontWeight = FontWeight.ExtraBold,
                             letterSpacing = (-1).sp, color = Ub.Accent)
                        if (!s.hideCategory) MonoLabel("Category · ${s.category}", size = 10)
                        val decoy = s.word
                        if (s.isDecoy && decoy != null) {
                            Text("Decoy word: $decoy", fontSize = 22.sp, fontWeight = FontWeight.Bold,
                                 color = Ub.Foreground)
                            Text("This isn't the real word — bluff carefully.",
                                 fontSize = 13.sp, color = Ub.Muted)
                        } else {
                            Text("Blend in. Give a clue vague enough to survive.",
                                 fontSize = 13.sp, color = Ub.Muted)
                        }
                    }
                } else {
                    Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel).padding(20.dp),
                           verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MonoLabel("Secret word", color = Ub.Accent)
                        Text(s.word ?: "—", fontSize = 36.sp, fontWeight = FontWeight.ExtraBold,
                             letterSpacing = (-1).sp, color = Ub.Foreground)
                        MonoLabel("Category · ${s.category}", size = 10)
                        Text("Drop a clue that proves you know it — without giving it away.",
                             fontSize = 13.sp, color = Ub.Muted)
                    }
                }
                if (s.firstPlayerName.isNotEmpty()) {
                    Column(Modifier.fillMaxWidth().ubCard().padding(16.dp),
                           verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        MonoLabel("Speaking order")
                        val who = if (s.firstPlayerId == ctx.yourId) "You go first"
                                  else "${s.firstPlayerName} goes first"
                        val dir = if (s.direction == "counterclockwise") "counter-clockwise" else "clockwise"
                        Text("$who — then continue $dir.", fontSize = 14.sp, color = Ub.Foreground)
                    }
                }
                InfoBanner("Waiting for the host to call a vote…")
            }
            "voting" -> {
                MonoLabel("Pick the imposter")
                val cells = s.players.filter { it.id != ctx.yourId }.map { it.id to it.name } +
                    listOf("__skip" to "Skip")
                cells.chunked(2).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for ((id, name) in row) Box(Modifier.weight(1f)) { PickCell(s, id, name) }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                Spacer(Modifier.height(2.dp))
                UbPrimaryButton(if (s.voted) "Vote in ✓" else "Lock in vote",
                    enabled = !s.voted && s.picked != null,
                    onClick = {
                        val payload = JSONObject().put("type", "vote")
                        if (s.picked == "__skip") payload.put("targetId", JSONObject.NULL)
                        else payload.put("targetId", s.picked ?: "")
                        ctx.client.send(payload); s.voted = true
                    })
            }
            "result" -> {
                val townWins = s.winner == "town"
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    MonoLabel("Result", color = Ub.Accent)
                    Text(if (townWins) "Town wins" else "Imposter wins", fontSize = 30.sp,
                         fontWeight = FontWeight.ExtraBold, letterSpacing = (-1).sp,
                         color = if (townWins) Ub.Foreground else Ub.Accent)
                }
                Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel).padding(16.dp),
                       verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val names = s.imposterIds.mapNotNull { id -> s.players.firstOrNull { it.id == id }?.name }
                    if (names.isNotEmpty()) {
                        val label = if (names.size == 1) "imposter was" else "imposters were"
                        Text("The $label ${names.joinToString(", ")}.",
                             fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                    }
                    val mv = s.mostVotedId
                    if (mv != null) {
                        val mvName = s.players.firstOrNull { it.id == mv }?.name ?: mv
                        Text("You voted out $mvName — ${if (s.imposterCaught) "correct!" else "wrong."}",
                             fontSize = 13.sp, color = Ub.Muted)
                    } else Text("The vote tied — no one was eliminated.", fontSize = 13.sp, color = Ub.Muted)
                    MonoLabel("Word · ${s.resultWord} (${s.category})", size = 10)
                }
            }
        }
    }
    } // Box(weight 1f)
    if (s.phase == gameOverPhase) {
        AdBanner(AdBannerPlacement.BETWEEN_ROUNDS, Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp))
    }
    } // Column(fillMaxSize)
    if (showInterstitial) {
        AdInterstitialController(show = showInterstitial) { showInterstitial = false }
    }
    } // Box(fillMaxSize)
    } // JamboreeTheme
}

private fun phaseLabel(s: ImposterGuestState): String = when (s.phase) {
    "playing" -> "Imposter · clue round"
    "voting" -> "Imposter · vote"
    "result" -> "Imposter · result"
    else -> "Imposter · lobby"
}

@Composable
private fun InfoBanner(text: String, accent: Boolean = false) {
    Box(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row,
            fill = if (accent) Ub.AccentSoft else Ub.Surface,
            stroke = if (accent) Ub.AccentLine else Ub.Line)
        .padding(horizontal = 16.dp, vertical = 14.dp)) {
        Text(text, fontSize = 14.sp, color = if (accent) Ub.Accent else Ub.Muted)
    }
}

@Composable
private fun PickCell(s: ImposterGuestState, id: String, name: String) {
    val selected = s.picked == id
    Row(Modifier.fillMaxWidth()
        .clip(RoundedCornerShape(10.dp))
        .background(if (selected) Ub.Accent else Color.White.copy(alpha = 0.05f))
        .then(if (selected) Modifier else Modifier.border(1.dp, Ub.LineStrong, RoundedCornerShape(10.dp)))
        .clickable(enabled = !s.voted) { s.picked = id }
        .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (id != "__skip") { Avatar(name, size = 24.dp); Spacer(Modifier.width(8.dp)) }
        Text(name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
             color = if (selected) Ub.OnAccent else Color.White)
    }
}

class ImposterGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean)
    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var category by mutableStateOf("")
    var word by mutableStateOf<String?>(null)
    var isImposter by mutableStateOf(false)
    var picked by mutableStateOf<String?>(null)
    var voted by mutableStateOf(false)
    var winner by mutableStateOf<String?>(null)
    var imposterIds by mutableStateOf<List<String>>(emptyList())
    var imposterCaught by mutableStateOf(false)
    var mostVotedId by mutableStateOf<String?>(null)
    var resultWord by mutableStateOf("")
    var hideCategory by mutableStateOf(false)
    var isDecoy by mutableStateOf(false)
    var firstPlayerId by mutableStateOf<String?>(null)
    var firstPlayerName by mutableStateOf("")
    var direction by mutableStateOf("clockwise")
    var error by mutableStateOf<String?>(null)
    var tutorialState by mutableStateOf(GuestTutorialState())
    var tutorialContent by mutableStateOf<GuestTutorialContent?>(null)
    var myTutorialVote by mutableStateOf<Boolean?>(null)
    var series by mutableStateOf(GuestSeriesState())

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
            "series_state" -> series = GuestSeriesState.from(m)
            "lobby" -> {
                val arr = m.optJSONArray("players") ?: return
                players = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"), o.optBoolean("isHost"))
                }
                phase = "lobby"
            }
            "role" -> {
                category = m.optString("category")
                word = if (m.isNull("word")) null else m.optString("word")
                isImposter = m.optBoolean("isImposter")
                hideCategory = m.optBoolean("hideCategory")
                isDecoy = m.optBoolean("isDecoy")
                firstPlayerId = if (m.isNull("firstPlayerId")) null else m.optString("firstPlayerId").ifEmpty { null }
                firstPlayerName = m.optString("firstPlayerName")
                direction = m.optString("direction", "clockwise")
                phase = "playing"; voted = false; picked = null
            }
            "voting" -> { phase = "voting"; voted = false; picked = null }
            "result" -> {
                phase = "result"
                winner = m.optString("winner")
                val arrIds = m.optJSONArray("imposterIds")
                imposterIds = if (arrIds != null) {
                    (0 until arrIds.length()).map { arrIds.getString(it) }
                } else if (m.has("imposterId") && !m.isNull("imposterId")) {
                    listOf(m.optString("imposterId"))
                } else emptyList()
                imposterCaught = m.optBoolean("imposterCaught")
                mostVotedId = if (m.isNull("mostVotedId")) null else m.optString("mostVotedId").ifEmpty { null }
                resultWord = m.optString("word")
                if (m.has("category")) category = m.optString("category")
                val arr = m.optJSONArray("players")
                if (arr != null) players = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"), o.optBoolean("isHost"))
                }
            }
            "reset" -> { phase = "lobby"; word = null; isImposter = false }
            "tutorial_vote_state" -> {
                tutorialState = GuestTutorialState.from(m)
                if (m.has("title")) {
                    tutorialContent = GuestTutorialContent(
                        m.optString("title"),
                        GuestTutorialContent.readSections(m.optJSONArray("sections")),
                        GuestTutorialContent.readSections(m.optJSONArray("menuSections")),
                    )
                }
            }
            "error" -> error = m.optString("message")
        }
    }
}
