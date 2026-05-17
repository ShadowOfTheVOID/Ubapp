package com.example.ubapp.games.codenames

import androidx.compose.foundation.background
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
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
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

    UbappTheme {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Column(
        Modifier
            .verticalScroll(rememberScrollState())
            .widthIn(max = 480.dp)
            .fillMaxWidth()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Playing as ${ctx.yourName}", style = MaterialTheme.typography.bodySmall)
        if (s.phase == "lobby") {
            TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                onVote = { yes -> s.myTutorialVote = yes
                    ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
            Text("Pick a team", style = MaterialTheme.typography.titleSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { ctx.client.send(JSONObject().put("type", "team").put("team", "red")) },
                       modifier = Modifier.weight(1f),
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFDC3545)))
                { Text("Join Red") }
                Button(onClick = { ctx.client.send(JSONObject().put("type", "team").put("team", "blue")) },
                       modifier = Modifier.weight(1f),
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0D6EFD)))
                { Text("Join Blue") }
            }
            OutlinedButton(onClick = {
                ctx.client.send(JSONObject().put("type", "spymaster").put("on", !s.isSpymaster))
            }, enabled = s.myTeam != null) {
                Text(if (s.isSpymaster) "Step down as spymaster" else "Be Spymaster")
            }
            Text("Players", style = MaterialTheme.typography.titleSmall)
            for (p in s.players) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(p.name + if (p.id == ctx.yourId) " — you" else "")
                    Spacer(Modifier.width(8.dp))
                    p.team?.let {
                        Text(it.uppercase(),
                             color = if (it == "red") Color(0xFFDC3545) else Color(0xFF0D6EFD),
                             style = MaterialTheme.typography.labelSmall)
                    }
                    if (p.isSpymaster) {
                        Spacer(Modifier.width(8.dp))
                        Text("spy", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
            Text("Need ≥2 per team and a spymaster each. Host starts when ready.",
                 style = MaterialTheme.typography.bodySmall)
            return@Column
        }

        // In-game board view (also used for gameOver).
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f).background(Color(0xFFDC3545), RoundedCornerShape(8.dp)).padding(8.dp),
                contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("RED", color = Color.White, style = MaterialTheme.typography.labelMedium)
                    Text("${s.redLeft}", color = Color.White, style = MaterialTheme.typography.titleLarge)
                }
            }
            Box(Modifier.weight(1f).background(Color(0xFF0D6EFD), RoundedCornerShape(8.dp)).padding(8.dp),
                contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("BLUE", color = Color.White, style = MaterialTheme.typography.labelMedium)
                    Text("${s.blueLeft}", color = Color.White, style = MaterialTheme.typography.titleLarge)
                }
            }
        }
        if (s.phase == "gameOver") {
            val color = if (s.winner == "red") Color(0xFFDC3545) else Color(0xFF0D6EFD)
            Box(Modifier.fillMaxWidth().background(color.copy(alpha = 0.2f), RoundedCornerShape(8.dp)).padding(12.dp)) {
                Text("${(s.winner ?: "").uppercase()} wins. ${s.endReason}",
                     style = MaterialTheme.typography.titleSmall)
            }
        } else {
            val color = if (s.currentTeam == "red") Color(0xFFDC3545) else Color(0xFF0D6EFD)
            Box(Modifier.fillMaxWidth().background(color.copy(alpha = 0.2f), RoundedCornerShape(8.dp)).padding(12.dp)) {
                Text("${(s.currentTeam ?: "").uppercase()}'s turn" +
                     (if (s.currentTeam == s.myTeam) " — you" else "") +
                     (if (s.isSpymaster) " (spymaster)" else ""),
                     style = MaterialTheme.typography.titleSmall)
            }
        }
        if (s.currentClue != null && s.phase != "gameOver") {
            Text("Clue: \"${s.currentClue}\" · ${s.currentNumber} · ${s.guessesLeft} left",
                 style = MaterialTheme.typography.bodyMedium,
                 modifier = Modifier.fillMaxWidth())
        } else if (s.isSpymaster && s.currentTeam == s.myTeam && s.phase != "gameOver") {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = clueText, onValueChange = { clueText = it },
                    label = { Text("Clue") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                    modifier = Modifier.weight(1f))
                OutlinedTextField(value = clueNum.toString(),
                    onValueChange = { v -> v.toIntOrNull()?.let { clueNum = it.coerceIn(0, 9) } },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true, modifier = Modifier.width(80.dp))
            }
            Button(onClick = {
                val c = clueText.trim()
                if (c.isNotEmpty()) {
                    ctx.client.send(JSONObject().put("type", "clue").put("clue", c).put("number", clueNum))
                    clueText = ""
                }
            }) { Text("Submit clue") }
        }
        // Board grid (5x5).
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (row in 0 until 5) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (col in 0 until 5) {
                        val i = row * 5 + col
                        if (i < s.board.size) Tile(s, i, ctx, Modifier.weight(1f))
                    }
                }
            }
        }
        if (s.phase != "gameOver" && !s.isSpymaster
            && s.currentTeam == s.myTeam && s.currentClue != null) {
            OutlinedButton(onClick = { ctx.client.send(JSONObject().put("type", "end_turn")) })
            { Text("End turn") }
        }
        if (s.lastEvent.isNotEmpty()) {
            Text(s.lastEvent, style = MaterialTheme.typography.bodySmall,
                 modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }
    }
    }
    }
}

@Composable
private fun Tile(s: CodenamesGuestState, i: Int, ctx: GuestContext, modifier: Modifier) {
    val card = s.board[i]
    val smKind: String? = if (s.isSpymaster && i < s.smView.size) s.smView[i] else null
    val canGuess = !s.isSpymaster && s.currentTeam == s.myTeam
        && s.currentClue != null && s.guessesLeft > 0
        && !card.revealed && s.phase != "gameOver"
    val bg: Color = when {
        card.revealed -> tileColor(card.kind)
        smKind != null -> tileColor(smKind).copy(alpha = 0.35f)
        else -> Color(0xFFD9C89B)
    }
    val fg: Color = if (card.revealed &&
                        (card.kind == "red" || card.kind == "blue" || card.kind == "assassin"))
                    Color.White else Color.Black
    Box(modifier
        .heightIn(min = 60.dp)
        .clip(RoundedCornerShape(6.dp))
        .background(bg)
        .alpha(if (card.revealed) 0.5f else 1.0f)
        .clickable(enabled = canGuess) {
            ctx.client.send(JSONObject().put("type", "guess").put("index", i))
        }
        .padding(4.dp),
        contentAlignment = Alignment.Center) {
        Text(card.word, color = fg, style = MaterialTheme.typography.labelMedium,
             textAlign = TextAlign.Center)
    }
}

private fun tileColor(kind: String): Color = when (kind) {
    "red" -> Color(0xFFDC3545)
    "blue" -> Color(0xFF0D6EFD)
    "neutral" -> Color(0xFFA89985)
    "assassin" -> Color(0xFF1F1F1F)
    else -> Color(0xFFD9C89B)
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

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
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
