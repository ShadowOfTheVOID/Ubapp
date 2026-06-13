package com.example.jamboree.games.codenames

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.ads.AdBanner
import com.example.jamboree.ads.AdBannerPlacement
import com.example.jamboree.ads.AdInterstitialController
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.UbSecondaryButton
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
fun CodenamesGuestScreen(ctx: GuestContext) {
    val s = remember { CodenamesGuestState() }
    var tick by remember { mutableIntStateOf(0) }
    var clueText by remember { mutableStateOf("") }
    var clueNum by remember { mutableStateOf(1) }
    DisposableEffect(ctx) {
        ctx.client.onMessage = { msg -> s.handle(msg); tick++ }
        for (m in ctx.replay) s.handle(m)
        onDispose { ctx.client.onMessage = null }
    }
    @Suppress("UNUSED_EXPRESSION") tick
    var showInterstitial by remember { mutableStateOf(false) }
    var interstitialFired by remember { mutableStateOf(false) }
    val gameOverPhase = "gameOver"
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
            .widthIn(max = 560.dp)
            .fillMaxWidth()
            .padding(20.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SeriesBannerCard(s.series)
        if (s.phase == "lobby") {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                MonoLabel("Code Words · lobby", color = Ub.Accent)
                Text("Pick your team", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
                     letterSpacing = (-0.8).sp, color = Ub.Foreground)
                Text("Playing as ${ctx.yourName}", fontSize = 13.sp, color = Ub.Muted)
            }
            TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                onVote = { yes -> s.myTutorialVote = yes
                    ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TeamPickButton("Join Red", s.myTeam == "red", Cn.Red, Modifier.weight(1f)) {
                    ctx.client.send(JSONObject().put("type", "team").put("team", "red"))
                }
                TeamPickButton("Join Blue", s.myTeam == "blue", Cn.Blue, Modifier.weight(1f)) {
                    ctx.client.send(JSONObject().put("type", "team").put("team", "blue"))
                }
            }
            UbSecondaryButton(if (s.isSpymaster) "Step down as spymaster" else "Become spymaster ★",
                enabled = s.myTeam != null,
                onClick = { ctx.client.send(JSONObject().put("type", "spymaster").put("on", !s.isSpymaster)) })
            MonoLabel("In the room · ${s.players.size}")
            for (p in s.players) {
                Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Avatar(p.name, host = p.isHost, size = 30.dp)
                    Spacer(Modifier.width(12.dp))
                    Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                    if (p.isSpymaster) {
                        Spacer(Modifier.width(8.dp))
                        MonoLabel("spy ★", size = 9, color = Cn.color(p.team ?: ""))
                    }
                    Spacer(Modifier.weight(1f))
                    p.team?.let { MonoLabel(it, size = 9, color = if (it == "red") Cn.Red else Cn.Blue) }
                }
            }
            Text("Need ≥2 per team and a spymaster each. Host starts when ready.",
                 fontSize = 12.sp, color = Ub.Muted)
            return@Column
        }

        // Header
        if (s.phase == "gameOver") {
            val w = s.winner ?: ""
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                MonoLabel("Game over", color = Cn.color(w))
                Text("${w.replaceFirstChar { it.uppercase() }} wins", fontSize = 28.sp,
                     fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.8).sp, color = Cn.color(w))
                if (s.endReason.isNotEmpty()) Text(s.endReason, fontSize = 13.sp, color = Ub.Muted)
            }
        } else {
            val team = s.currentTeam ?: ""
            val mine = s.currentTeam == s.myTeam
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                MonoLabel("Code Words", color = Ub.Accent)
                Text(if (mine) (if (s.isSpymaster) "Your clue" else "Your team guesses")
                     else "${team.replaceFirstChar { it.uppercase() }}'s turn",
                     fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.7).sp,
                     color = if (mine) Cn.color(team) else Ub.Foreground)
            }
        }
        // Scoreboard
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TeamScore("Red", s.redLeft, Cn.Red, Modifier.weight(1f))
            TeamScore("Blue", s.blueLeft, Cn.Blue, Modifier.weight(1f))
        }
        // Clue
        if (s.currentClue != null && s.phase != "gameOver") {
            Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel).padding(14.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    MonoLabel("Clue", size = 9, color = Cn.color(s.currentTeam ?: ""))
                    Text("“${s.currentClue}”", fontFamily = FontFamily.Serif,
                         fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground)
                }
                Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp))
                    .background(Cn.color(s.currentTeam ?: "")), contentAlignment = Alignment.Center) {
                    Text("${s.currentNumber}", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
                }
                Spacer(Modifier.width(8.dp))
                MonoLabel("${s.guessesLeft} left", size = 9, color = Ub.Faint)
            }
        } else if (s.isSpymaster && s.currentTeam == s.myTeam && s.phase != "gameOver") {
            MonoLabel("Compose clue · one word + a number")
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = clueText, onValueChange = { clueText = it },
                    label = { Text("WORD") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                    modifier = Modifier.weight(1f))
                OutlinedTextField(value = clueNum.toString(),
                    onValueChange = { v -> v.toIntOrNull()?.let { clueNum = it.coerceIn(0, 9) } },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true, modifier = Modifier.width(80.dp))
            }
            UbPrimaryButton("Give clue →", enabled = clueText.trim().isNotEmpty(), onClick = {
                val c = clueText.trim()
                if (c.isNotEmpty()) {
                    ctx.client.send(JSONObject().put("type", "clue").put("clue", c).put("number", clueNum))
                    clueText = ""
                }
            })
        }
        // Board grid (5x5).
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Ub.Radius.card))
            .background(Color(0xFF1A1A1A)).border(1.dp, Ub.Line, RoundedCornerShape(Ub.Radius.card))
            .padding(8.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            for (row in 0 until 5) {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    for (col in 0 until 5) {
                        val i = row * 5 + col
                        if (i < s.board.size) Tile(s, i, ctx, Modifier.weight(1f))
                    }
                }
            }
        }
        if (s.phase != "gameOver" && !s.isSpymaster
            && s.currentTeam == s.myTeam && s.currentClue != null) {
            UbSecondaryButton("End turn", onClick = { ctx.client.send(JSONObject().put("type", "end_turn")) })
        }
        if (s.lastEvent.isNotEmpty()) MonoLabel(s.lastEvent, size = 10)
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

@Composable
private fun TeamPickButton(title: String, selected: Boolean, color: Color, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier
        .clip(RoundedCornerShape(Ub.Radius.button))
        .background(if (selected) color else color.copy(alpha = 0.12f))
        .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(Ub.Radius.button))
        .clickable(onClick = onClick)
        .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center) {
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold,
             color = if (selected) Color.White else color)
    }
}

@Composable
private fun TeamScore(name: String, left: Int, color: Color, modifier: Modifier) {
    Column(modifier
        .clip(RoundedCornerShape(Ub.Radius.row))
        .background(color.copy(alpha = 0.10f))
        .border(1.dp, color.copy(alpha = 0.35f), RoundedCornerShape(Ub.Radius.row))
        .padding(horizontal = 14.dp, vertical = 12.dp)) {
        MonoLabel("$name · left", size = 10, color = color)
        Text("$left", fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, color = color)
    }
}

@Composable
private fun Tile(s: CodenamesGuestState, i: Int, ctx: GuestContext, modifier: Modifier) {
    val card = s.board[i]
    val smKind: String? = if (s.isSpymaster && i < s.smView.size) s.smView[i] else null
    val canGuess = !s.isSpymaster && s.currentTeam == s.myTeam
        && s.currentClue != null && s.guessesLeft > 0
        && !card.revealed && s.phase != "gameOver"
    val showColor = card.revealed || s.phase == "gameOver" || smKind != null
    val kind = if (card.revealed || s.phase == "gameOver") card.kind else (smKind ?: "")
    val bg = if (showColor && kind.isNotEmpty()) Cn.color(kind) else Cn.Paper
    val fg = if (showColor && kind.isNotEmpty()) Cn.ink(kind) else Cn.PaperInk
    Box(modifier
        .heightIn(min = 50.dp)
        .clip(RoundedCornerShape(6.dp))
        .background(bg)
        .border(if (canGuess) 2.dp else 1.dp,
                if (canGuess) Cn.color(s.myTeam ?: "") else Color.Black.copy(alpha = 0.25f),
                RoundedCornerShape(6.dp))
        .alpha(if (card.revealed) 0.72f else 1.0f)
        .clickable(enabled = canGuess) {
            ctx.client.send(JSONObject().put("type", "guess").put("index", i))
        }
        .padding(3.dp),
        contentAlignment = Alignment.Center) {
        Text(card.word, color = fg, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold,
             fontSize = 11.sp, textAlign = TextAlign.Center, maxLines = 1)
    }
}

private object Cn {
    val Red = Color(0xFFFF5A4A)
    val RedInk = Color(0xFF3A0A04)
    val Blue = Color(0xFF4F9EFF)
    val BlueInk = Color(0xFF02152E)
    val Bystander = Color(0xFFD8C590)
    val BystanderInk = Color(0xFF2A2410)
    val Assassin = Color(0xFF0E0E10)
    val Paper = Color(0xFFF3ECD6)
    val PaperInk = Color(0xFF1C1C1F)
    fun color(kind: String): Color = when (kind) {
        "red" -> Red; "blue" -> Blue; "assassin" -> Assassin
        "neutral", "bystander" -> Bystander; else -> Bystander
    }
    fun ink(kind: String): Color = when (kind) {
        "red" -> RedInk; "blue" -> BlueInk; "assassin" -> Color.White; else -> BystanderInk
    }
}

class CodenamesGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean,
                      val team: String?, val isSpymaster: Boolean)
    data class Tile(val word: String, val kind: String, val revealed: Boolean)

    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var board by mutableStateOf<List<Tile>>(emptyList())
    var smView by mutableStateOf<List<String>>(emptyList())
    var isSpymaster by mutableStateOf(false)
    var myTeam by mutableStateOf<String?>(null)
    var currentTeam by mutableStateOf<String?>(null)
    var currentClue by mutableStateOf<String?>(null)
    var currentNumber by mutableIntStateOf(0)
    var guessesLeft by mutableIntStateOf(0)
    var redLeft by mutableIntStateOf(0)
    var blueLeft by mutableIntStateOf(0)
    var winner by mutableStateOf<String?>(null)
    var endReason by mutableStateOf("")
    var lastEvent by mutableStateOf("")
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
                    Player(o.optString("id"), o.optString("name"), o.optBoolean("isHost"),
                           o.optString("team").ifEmpty { null }, o.optBoolean("isSpymaster"))
                }
                phase = "lobby"
            }
            "role" -> {
                isSpymaster = m.optBoolean("isSpymaster")
                myTeam = m.optString("team").ifEmpty { null }
                val sm = m.optJSONArray("smView")
                smView = if (sm == null) emptyList() else (0 until sm.length()).map {
                    sm.getJSONObject(it).optString("kind")
                }
            }
            "state" -> {
                val b = m.optJSONArray("board")
                if (b != null) board = (0 until b.length()).map {
                    val o = b.getJSONObject(it)
                    Tile(o.optString("word"), o.optString("kind"), o.optBoolean("revealed"))
                }
                currentTeam = m.optString("currentTeam").ifEmpty { null }
                currentClue = if (m.isNull("currentClue")) null else m.optString("currentClue").ifEmpty { null }
                currentNumber = m.optInt("currentNumber", 0)
                guessesLeft = m.optInt("guessesLeft", 0)
                redLeft = m.optInt("redLeft", redLeft)
                blueLeft = m.optInt("blueLeft", blueLeft)
                phase = m.optString("phase", phase)
                winner = if (m.isNull("winner")) null else m.optString("winner").ifEmpty { null }
                endReason = m.optString("endReason", "")
                lastEvent = m.optString("lastEvent", "")
            }
            "reset" -> { phase = "lobby"; board = emptyList(); winner = null; smView = emptyList() }
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
        }
    }
}
