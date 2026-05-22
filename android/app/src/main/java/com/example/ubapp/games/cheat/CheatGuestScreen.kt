package com.example.ubapp.games.cheat

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestSeriesState
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.SeriesBannerCard
import com.example.ubapp.join.TutorialGuestCard
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun CheatGuestScreen(ctx: GuestContext) {
    val s = remember { CheatGuestState() }
    var tick by remember { mutableIntStateOf(0) }
    val selected = remember { mutableStateListOf<String>() }
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
                SeriesBannerCard(s.series)
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
                        Text("${winner?.name ?: "?"} wins!", style = MaterialTheme.typography.titleLarge)
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
                                if (s.pileSize > 0) {
                                    Box(modifier = Modifier.size(80.dp, 90.dp),
                                        contentAlignment = Alignment.Center) {
                                        // Jittered stack of card backs.
                                        for (i in 0 until minOf(s.pileSize, 4)) {
                                            Box(modifier = Modifier
                                                .offset(x = (i * 1.5f).dp, y = (i * 1.5f).dp)
                                                .rotate(if (i % 2 == 0) -(i + 1).toFloat() else (i + 1).toFloat())) {
                                                com.example.ubapp.games.cards.GridCardBack(width = 56.dp)
                                            }
                                        }
                                    }
                                }
                                Text("Pile: ${s.pileSize} card${if (s.pileSize == 1) "" else "s"}",
                                     style = MaterialTheme.typography.bodyMedium)
                                val lp = s.lastPlay
                                if (lp != null) {
                                    val accuser = s.players.firstOrNull { it.id == lp.playerId }?.name ?: "?"
                                    Text("$accuser claimed ${lp.count} × ${rankName(lp.claimedRank)}",
                                         style = MaterialTheme.typography.titleSmall,
                                         fontWeight = FontWeight.Bold)
                                } else {
                                    Text("No open play", style = MaterialTheme.typography.titleSmall)
                                }
                                Text("Next expected: ${rankName(s.expectedRank)}",
                                     style = MaterialTheme.typography.bodySmall)
                                if (s.lastEvent.isNotEmpty())
                                    Text(s.lastEvent, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                        val reveal = s.lastReveal
                        if (reveal != null) {
                            ElevatedCard(Modifier.fillMaxWidth()) {
                                Column(Modifier.padding(12.dp)) {
                                    Text(if (reveal.truthful) "Truthful claim" else "Caught cheating!",
                                         style = MaterialTheme.typography.titleSmall)
                                    val caller = s.players.firstOrNull { it.id == reveal.callerId }?.name ?: "?"
                                    val accused = s.players.firstOrNull { it.id == reveal.accusedId }?.name ?: "?"
                                    val loser = s.players.firstOrNull { it.id == reveal.loserId }?.name ?: "?"
                                    Text("$caller called BS on $accused (${rankName(reveal.claimedRank)})",
                                         style = MaterialTheme.typography.bodySmall)
                                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        for (c in reveal.cards) CardFace(c, small = true)
                                    }
                                    Text("$loser picks up the pile.",
                                         style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }
                        if (s.phase == "pendingWin") {
                            val w = s.players.firstOrNull { it.id == s.winnerId }
                            ElevatedCard(Modifier.fillMaxWidth()) {
                                Column(Modifier.padding(12.dp)) {
                                    Text("Pending win", style = MaterialTheme.typography.titleSmall)
                                    Text("${w?.name ?: "?"} played their last card claiming ${rankName(s.lastPlay?.claimedRank ?: 0)}.",
                                         style = MaterialTheme.typography.bodySmall)
                                    if (ctx.yourId != s.winnerId) {
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Button(
                                                onClick = { ctx.client.send(JSONObject().put("type", "bs")) },
                                                modifier = Modifier.weight(1f),
                                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828)),
                                            ) { Text("Call BS") }
                                            Button(
                                                onClick = { ctx.client.send(JSONObject().put("type", "accept_win")) },
                                                modifier = Modifier.weight(1f),
                                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)),
                                            ) { Text("Accept win") }
                                        }
                                    } else {
                                        Text("Wait for the others to call BS or accept.",
                                             style = MaterialTheme.typography.bodySmall)
                                    }
                                }
                            }
                        }
                        if (s.currentId == ctx.yourId && s.phase == "playing") {
                            Text("Your turn — pick cards and play as ${rankName(s.expectedRank)}",
                                 style = MaterialTheme.typography.titleSmall, color = Color(0xFF7BD389))
                        }
                        Text("Your hand (${s.hand.size})", style = MaterialTheme.typography.titleSmall)
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(70.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                            modifier = Modifier.heightIn(max = 360.dp),
                        ) {
                            items(s.hand) { c ->
                                val key = "${c.suit}-${c.rank}"
                                val sel = selected.contains(key)
                                val canSelect = s.currentId == ctx.yourId && s.phase == "playing"
                                Box(Modifier
                                    .alpha(if (canSelect) 1f else 0.7f)
                                    .clickable(enabled = canSelect) {
                                        if (sel) selected.remove(key) else selected.add(key)
                                    }
                                    .then(if (sel) Modifier.border(3.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(8.dp))
                                          else Modifier)
                                ) { CardFace(c) }
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth()) {
                            val canBs = s.lastPlay != null && s.lastPlay!!.playerId != ctx.yourId && s.phase == "playing"
                            if (canBs) {
                                Button(onClick = { ctx.client.send(JSONObject().put("type", "bs")) },
                                       modifier = Modifier.weight(1f),
                                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828))
                                ) { Text("Call BS") }
                            }
                            if (s.currentId == ctx.yourId && s.phase == "playing") {
                                Button(
                                    enabled = selected.isNotEmpty(),
                                    onClick = {
                                        val picked = s.hand.filter { selected.contains("${it.suit}-${it.rank}") }
                                        if (picked.isEmpty()) return@Button
                                        val arr = JSONArray()
                                        for (c in picked) arr.put(JSONObject().put("suit", c.suit).put("rank", c.rank))
                                        ctx.client.send(JSONObject().put("type", "play")
                                            .put("claimedRank", s.expectedRank).put("cards", arr))
                                        selected.clear()
                                    },
                                    modifier = Modifier.weight(1f),
                                ) { Text("Play ${selected.size} × ${rankName(s.expectedRank)}") }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CardFace(c: CheatGuestState.Card, small: Boolean = false) {
    val w = if (small) 48.dp else 70.dp
    val suit = com.example.ubapp.games.cards.CardSuit.fromWire(c.suit)
    if (suit != null) {
        com.example.ubapp.games.cards.NoirCardFace(rank = c.rank, suit = suit, width = w)
    } else {
        com.example.ubapp.games.cards.GridCardBack(width = w)
    }
}

private fun suitGlyph(s: String): String = when (s) {
    "clubs" -> "♣"; "diamonds" -> "♦"; "hearts" -> "♥"; "spades" -> "♠"; else -> ""
}
private fun rankShort(r: Int): String = when (r) {
    1 -> "A"; 11 -> "J"; 12 -> "Q"; 13 -> "K"; else -> r.toString()
}
private fun rankName(r: Int): String = when (r) {
    1 -> "Aces"; 11 -> "Jacks"; 12 -> "Queens"; 13 -> "Kings"; else -> "${r}s"
}

class CheatGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean, val handCount: Int)
    data class Card(val suit: String, val rank: Int)
    data class LastPlay(val playerId: String, val claimedRank: Int, val count: Int)
    data class Reveal(val callerId: String, val accusedId: String, val claimedRank: Int,
                      val cards: List<Card>, val truthful: Boolean, val loserId: String)

    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var hand by mutableStateOf<List<Card>>(emptyList())
    var pileSize by mutableIntStateOf(0)
    var expectedRank by mutableIntStateOf(1)
    var lastPlay by mutableStateOf<LastPlay?>(null)
    var lastReveal by mutableStateOf<Reveal?>(null)
    var currentId by mutableStateOf<String?>(null)
    var winnerId by mutableStateOf<String?>(null)
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
                pileSize = m.optInt("pileSize", pileSize)
                expectedRank = m.optInt("expectedRank", expectedRank)
                currentId = m.optString("currentId").ifEmpty { null }
                winnerId = m.optString("winnerId").ifEmpty { null }
                lastEvent = m.optString("lastEvent", "")
                val lp = m.optJSONObject("lastPlay")
                lastPlay = lp?.let { LastPlay(it.optString("playerId"),
                                              it.optInt("claimedRank"),
                                              it.optInt("count")) }
                val r = m.optJSONObject("lastReveal")
                lastReveal = r?.let {
                    val cs = it.optJSONArray("cards")
                    val cards = if (cs == null) emptyList()
                                else (0 until cs.length()).map { i ->
                                    val o = cs.getJSONObject(i)
                                    Card(o.optString("suit"), o.optInt("rank"))
                                }
                    Reveal(it.optString("callerId"), it.optString("accusedId"),
                           it.optInt("claimedRank"), cards, it.optBoolean("truthful"),
                           it.optString("loserId"))
                }
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
            "reset" -> { phase = "lobby"; hand = emptyList(); winnerId = null
                         lastPlay = null; lastReveal = null; pileSize = 0; lastEvent = "" }
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
