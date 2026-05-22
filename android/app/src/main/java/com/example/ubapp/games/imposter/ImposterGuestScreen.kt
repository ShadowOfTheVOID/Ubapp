package com.example.ubapp.games.imposter

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
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

    UbappTheme {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Column(
        Modifier
            .verticalScroll(rememberScrollState())
            .widthIn(max = 480.dp)
            .fillMaxWidth()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Playing as ${ctx.yourName}", style = MaterialTheme.typography.bodySmall)
        if (s.error != null) Text(s.error!!, color = MaterialTheme.colorScheme.error)
        when (s.phase) {
            "lobby" -> {
                TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                    onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                    onVote = { yes -> s.myTutorialVote = yes
                        ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                Text("Players (${s.players.size})", style = MaterialTheme.typography.titleSmall)
                for (p in s.players) Text(p.name + if (p.isHost) " (host)" else "")
            }
            "playing" -> {
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp),
                           horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("YOUR ROLE", style = MaterialTheme.typography.labelSmall)
                        if (s.isImposter) {
                            Text("IMPOSTER",
                                 style = MaterialTheme.typography.displayMedium,
                                 color = Color(0xFFC62828))
                            if (!s.hideCategory) {
                                Text("Category: ${s.category}",
                                     style = MaterialTheme.typography.bodyMedium)
                            }
                            val decoy = s.word
                            if (s.isDecoy && decoy != null) {
                                Text("Decoy word: $decoy",
                                     style = MaterialTheme.typography.titleLarge)
                                Text("This isn't the real word — bluff carefully.",
                                     style = MaterialTheme.typography.bodySmall)
                            } else {
                                Text("Bluff your way through.",
                                     style = MaterialTheme.typography.bodySmall)
                            }
                        } else {
                            Text("SECRET WORD",
                                 style = MaterialTheme.typography.labelSmall)
                            Text(s.word ?: "—",
                                 style = MaterialTheme.typography.displaySmall)
                            Text("Category: ${s.category}",
                                 style = MaterialTheme.typography.bodyMedium)
                            Text("Find the imposter.",
                                 style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
                if (s.firstPlayerName.isNotEmpty()) {
                    ElevatedCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp),
                               horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("TURN ORDER", style = MaterialTheme.typography.labelSmall)
                            val who = if (s.firstPlayerId == ctx.yourId) "You go first"
                                      else "${s.firstPlayerName} goes first"
                            val dir = if (s.direction == "counterclockwise") "counter-clockwise"
                                      else "clockwise"
                            Text("$who — then continue $dir.",
                                 style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                Text("Waiting for the host to call a vote…",
                     style = MaterialTheme.typography.bodySmall)
            }
            "voting" -> {
                Text("Pick the imposter", style = MaterialTheme.typography.titleSmall)
                val others = s.players.filter { it.id != ctx.yourId }
                for (p in others) OutlinedButton(
                    onClick = { s.picked = p.id }, modifier = Modifier.fillMaxWidth(),
                    enabled = !s.voted,
                ) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween)
                    { Text(p.name); if (s.picked == p.id) Text("✓") }
                }
                OutlinedButton(onClick = { s.picked = "__skip" }, modifier = Modifier.fillMaxWidth(),
                               enabled = !s.voted) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween)
                    { Text("Skip"); if (s.picked == "__skip") Text("✓") }
                }
                Button(onClick = {
                    val payload = JSONObject().put("type", "vote")
                    if (s.picked == "__skip") payload.put("targetId", JSONObject.NULL)
                    else payload.put("targetId", s.picked ?: "")
                    ctx.client.send(payload); s.voted = true
                }, enabled = !s.voted && s.picked != null) {
                    Text(if (s.voted) "Vote in ✓" else "Lock in vote")
                }
            }
            "result" -> {
                val winner = if (s.winner == "town") "Town wins" else "Imposter wins"
                Text(winner, style = MaterialTheme.typography.headlineSmall)
                val names = s.imposterIds.mapNotNull { id ->
                    s.players.firstOrNull { it.id == id }?.name
                }
                if (names.isNotEmpty()) {
                    val label = if (names.size == 1) "imposter was" else "imposters were"
                    Text("The $label ${names.joinToString(", ")}.")
                }
                val mv = s.mostVotedId
                if (mv != null) {
                    val mvName = s.players.firstOrNull { it.id == mv }?.name ?: mv
                    Text("You voted out $mvName — ${if (s.imposterCaught) "correct!" else "wrong."}")
                } else Text("The vote tied — no one was eliminated.")
                Text("Secret word was ${s.resultWord} (${s.category}).",
                     style = MaterialTheme.typography.bodySmall)
            }
        }
    }
    }
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

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
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
