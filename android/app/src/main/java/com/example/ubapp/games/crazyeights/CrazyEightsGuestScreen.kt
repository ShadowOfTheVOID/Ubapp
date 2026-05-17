package com.example.ubapp.games.crazyeights

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
import org.json.JSONObject

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CrazyEightsGuestScreen(ctx: GuestContext) {
    val s = remember { CrazyEightsGuestState() }
    var tick by remember { mutableIntStateOf(0) }
    var suitPickFor by remember { mutableStateOf<CrazyEightsGuestState.Card?>(null) }
    DisposableEffect(ctx) {
        ctx.client.onMessage = { msg -> s.handle(msg); tick++ }
        for (m in ctx.replay) s.handle(m)
        onDispose { ctx.client.onMessage = null }
    }
    @Suppress("UNUSED_EXPRESSION") tick

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Playing as ${ctx.yourName}", style = MaterialTheme.typography.bodySmall)
        when (s.phase) {
            "lobby" -> {
                TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                    onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                    onVote = { yes -> s.myTutorialVote = yes
                        ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                Text("Players (${s.players.size})", style = MaterialTheme.typography.titleSmall)
                for (p in s.players) Text(p.name + if (p.isHost) " (host)" else "")
            }
            "gameOver" -> {
                val winner = s.players.firstOrNull { it.id == s.winnerId }
                Text("Game over", style = MaterialTheme.typography.headlineSmall)
                Text("${winner?.name ?: "?"} wins!",
                     style = MaterialTheme.typography.titleLarge)
                for (p in s.players) Row(Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween)
                { Text(p.name); Text("${p.handCount} cards left") }
            }
            else -> {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (p in s.players) {
                        val isCurrent = s.currentId == p.id
                        Column(Modifier
                            .background(
                                if (isCurrent) MaterialTheme.colorScheme.primary else Color(0xFF373D45),
                                RoundedCornerShape(8.dp))
                            .padding(8.dp)) {
                            Text(p.name + if (p.id == ctx.yourId) " (you)" else "",
                                 style = MaterialTheme.typography.labelMedium,
                                 color = if (isCurrent) Color.White else Color(0xFFE6EDF3))
                            Text("${p.handCount} cards",
                                 style = MaterialTheme.typography.labelSmall,
                                 color = if (isCurrent) Color.White else Color(0xFFA0A8B0))
                        }
                    }
                }
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp),
                           horizontalAlignment = Alignment.CenterHorizontally) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier
                                .background(Color(0xFF0D2A1F), RoundedCornerShape(8.dp))
                                .size(70.dp, 100.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center) {
                                Text("${s.drawCount}",
                                     style = MaterialTheme.typography.titleLarge,
                                     color = Color(0xFF9DA7B3))
                                Text("draw", style = MaterialTheme.typography.labelSmall,
                                     color = Color(0xFF9DA7B3))
                            }
                            val top = s.topCard
                            if (top != null) CardFace(top)
                            else Spacer(Modifier.size(70.dp, 100.dp))
                        }
                        Text("Active suit: ${suitGlyph(s.activeSuit ?: s.topCard?.suit ?: "")}",
                             style = MaterialTheme.typography.bodyMedium)
                        Text(if (s.currentId == ctx.yourId) "Your turn"
                             else "${s.players.firstOrNull { it.id == s.currentId }?.name ?: ""}'s turn",
                             style = MaterialTheme.typography.titleSmall)
                        if (s.lastEvent.isNotEmpty())
                            Text(s.lastEvent, style = MaterialTheme.typography.bodySmall)
                    }
                }
                Text("Your hand (${s.hand.size})", style = MaterialTheme.typography.titleSmall)
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(70.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.heightIn(max = 320.dp),
                ) {
                    items(s.hand) { c ->
                        val playable = s.isPlayable(c) && s.currentId == ctx.yourId
                        Box(Modifier
                            .alpha(if (playable) 1f else 0.4f)
                            .clickable(enabled = playable) {
                                if (c.rank == 8) suitPickFor = c
                                else ctx.client.send(JSONObject().put("type", "play")
                                    .put("suit", c.suit).put("rank", c.rank))
                            }) { CardFace(c) }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (s.currentId == ctx.yourId && s.justDrew) {
                        OutlinedButton(onClick = { ctx.client.send(JSONObject().put("type", "pass")) })
                        { Text("Pass") }
                    }
                    if (s.currentId == ctx.yourId) {
                        OutlinedButton(
                            onClick = { ctx.client.send(JSONObject().put("type", "draw")) },
                            enabled = !s.justDrew,
                        ) { Text("Draw") }
                    }
                }
            }
        }
    }
    suitPickFor?.let { card ->
        AlertDialog(onDismissRequest = { suitPickFor = null },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { suitPickFor = null }) { Text("Cancel") } },
            title = { Text("Declare a new suit") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (suit in listOf("clubs", "diamonds", "hearts", "spades")) {
                        Button(onClick = {
                            ctx.client.send(JSONObject().put("type", "play")
                                .put("suit", card.suit).put("rank", card.rank)
                                .put("declaredSuit", suit))
                            suitPickFor = null
                        }, modifier = Modifier.fillMaxWidth()) {
                            Text(suitGlyph(suit), style = MaterialTheme.typography.headlineMedium,
                                 color = if (suit == "diamonds" || suit == "hearts") Color(0xFFC62828) else Color.White)
                        }
                    }
                }
            }
        )
    }
}

@Composable
private fun CardFace(c: CrazyEightsGuestState.Card) {
    val red = c.suit == "diamonds" || c.suit == "hearts"
    Box(Modifier
        .size(70.dp, 100.dp)
        .background(Color.White, RoundedCornerShape(8.dp))
        .padding(6.dp)) {
        Text(rankShort(c.rank),
             style = MaterialTheme.typography.titleMedium,
             color = if (red) Color(0xFFC62828) else Color.Black,
             modifier = Modifier.align(Alignment.TopStart))
        Text(suitGlyph(c.suit),
             style = MaterialTheme.typography.headlineMedium,
             color = if (red) Color(0xFFC62828) else Color.Black,
             modifier = Modifier.align(Alignment.BottomEnd))
    }
}

private fun suitGlyph(s: String): String = when (s) {
    "clubs" -> "♣"; "diamonds" -> "♦"; "hearts" -> "♥"; "spades" -> "♠"; else -> ""
}
private fun rankShort(r: Int): String = when (r) {
    11 -> "J"; 12 -> "Q"; 13 -> "K"; 14 -> "A"; else -> r.toString()
}

class CrazyEightsGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean, val handCount: Int)
    data class Card(val suit: String, val rank: Int)

    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var hand by mutableStateOf<List<Card>>(emptyList())
    var topCard by mutableStateOf<Card?>(null)
    var activeSuit by mutableStateOf<String?>(null)
    var drawCount by mutableIntStateOf(0)
    var currentId by mutableStateOf<String?>(null)
    var justDrew by mutableStateOf(false)
    var winnerId by mutableStateOf<String?>(null)
    var lastEvent by mutableStateOf("")
    var tutorialState by mutableStateOf(GuestTutorialState())
    var tutorialContent by mutableStateOf<GuestTutorialContent?>(null)
    var myTutorialVote by mutableStateOf<Boolean?>(null)

    fun isPlayable(c: Card): Boolean {
        val top = topCard ?: return true
        if (c.rank == 8) return true
        val active = activeSuit ?: top.suit
        return c.suit == active || c.rank == top.rank
    }

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
            "lobby" -> {
                val arr = m.optJSONArray("players") ?: return
                players = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"),
                           o.optBoolean("isHost"), o.optInt("handCount", 0))
                }
                phase = "lobby"
            }
            "state" -> {
                phase = m.optString("phase", phase)
                val arr = m.optJSONArray("players")
                if (arr != null) players = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"),
                           o.optBoolean("isHost"), o.optInt("handCount", 0))
                }
                val top = m.optJSONObject("topCard")
                topCard = top?.let { Card(it.optString("suit"), it.optInt("rank")) }
                activeSuit = if (m.isNull("activeSuit")) null else m.optString("activeSuit").ifEmpty { null }
                drawCount = m.optInt("drawCount", drawCount)
                currentId = m.optString("currentId").ifEmpty { null }
                justDrew = m.optBoolean("justDrew", false)
                lastEvent = m.optString("lastEvent", "")
            }
            "hand" -> {
                val arr = m.optJSONArray("cards") ?: return
                hand = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Card(o.optString("suit"), o.optInt("rank"))
                }
            }
            "over" -> {
                phase = "gameOver"
                winnerId = m.optString("winnerId").ifEmpty { null }
                val arr = m.optJSONArray("players")
                if (arr != null) players = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"),
                           o.optBoolean("isHost"), o.optInt("handCount", 0))
                }
            }
            "reset" -> { phase = "lobby"; hand = emptyList(); winnerId = null }
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
