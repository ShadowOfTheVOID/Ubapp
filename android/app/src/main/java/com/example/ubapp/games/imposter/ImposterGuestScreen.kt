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
        onDispose { }
    }
    @Suppress("UNUSED_EXPRESSION") tick

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
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
                            Text("Category: ${s.category}",
                                 style = MaterialTheme.typography.bodyMedium)
                            Text("Bluff your way through.",
                                 style = MaterialTheme.typography.bodySmall)
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
                val imposterName = s.players.firstOrNull { it.id == s.imposterId }?.name ?: "?"
                Text("The imposter was $imposterName.")
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
    var imposterId by mutableStateOf<String?>(null)
    var imposterCaught by mutableStateOf(false)
    var mostVotedId by mutableStateOf<String?>(null)
    var resultWord by mutableStateOf("")
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
                phase = "playing"; voted = false; picked = null
            }
            "voting" -> { phase = "voting"; voted = false; picked = null }
            "result" -> {
                phase = "result"
                winner = m.optString("winner")
                imposterId = m.optString("imposterId")
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
