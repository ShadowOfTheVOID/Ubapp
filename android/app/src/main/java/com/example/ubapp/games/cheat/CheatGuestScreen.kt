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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.theme.Avatar
import com.example.ubapp.theme.MonoLabel
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.UbPrimaryButton
import com.example.ubapp.theme.UbSecondaryButton
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.theme.ubCard
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
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
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
                SeriesBannerCard(s.series)
                when (s.phase) {
                    "lobby" -> {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            MonoLabel("Cheat · lobby", color = Ub.Accent)
                            Text("Waiting for the deal", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
                                 letterSpacing = (-0.8).sp, color = Ub.Foreground)
                            Text("Playing as ${ctx.yourName}", fontSize = 13.sp, color = Ub.Muted)
                        }
                        TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                            onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                            onVote = { yes -> s.myTutorialVote = yes
                                ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                        MonoLabel("In the room · ${s.players.size}")
                        for (p in s.players) PlayerRow(p.name, p.isHost, p.id == ctx.yourId)
                    }
                    "gameOver" -> {
                        val winner = s.players.firstOrNull { it.id == s.winnerId }
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            MonoLabel("Game over", color = Ub.Accent)
                            Text("${winner?.name ?: "?"} wins", fontSize = 28.sp,
                                 fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.8).sp, color = Ub.Foreground)
                        }
                        MonoLabel("Final standings")
                        for (p in s.players.sortedBy { it.handCount }) {
                            Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                Avatar(p.name, host = p.isHost, size = 30.dp)
                                Spacer(Modifier.width(12.dp))
                                Text(p.name + if (p.id == s.winnerId) "  🏆" else "",
                                     fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                                Spacer(Modifier.weight(1f))
                                MonoLabel("${p.handCount} left", size = 10)
                            }
                        }
                    }
                    else -> {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            MonoLabel("Cheat", color = Ub.Accent)
                            val mine = s.currentId == ctx.yourId && s.phase == "playing"
                            Text(if (mine) "Your turn"
                                 else "${s.players.firstOrNull { it.id == s.currentId }?.name ?: ""}'s turn",
                                 fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.8).sp,
                                 color = if (mine) Ub.Accent else Ub.Foreground)
                            Text("Claim ${rankName(s.expectedRank)} face-down — lie if you must.",
                                 fontSize = 13.sp, color = Ub.Muted)
                        }
                        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            for (p in s.players) PlayerChip(p.name, p.isHost, p.handCount, s.currentId == p.id)
                        }
                        // Pile
                        Column(
                            Modifier.fillMaxWidth()
                                .clip(RoundedCornerShape(Ub.Radius.hero))
                                .background(Brush.radialGradient(
                                    listOf(Ub.Accent.copy(alpha = 0.12f), Color.Transparent), radius = 420f))
                                .padding(vertical = 24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            if (s.pileSize > 0) {
                                Box(Modifier.size(82.dp, 92.dp), contentAlignment = Alignment.Center) {
                                    for (i in 0 until minOf(s.pileSize, 4)) {
                                        Box(Modifier
                                            .offset(x = (i * 1.5f).dp, y = (i * 1.5f).dp)
                                            .rotate(if (i % 2 == 0) -(i + 1).toFloat() else (i + 1).toFloat())) {
                                            com.example.ubapp.games.cards.GridCardBack(width = 60.dp)
                                        }
                                    }
                                }
                            }
                            MonoLabel("Pile · ${s.pileSize}", size = 10)
                            val lp = s.lastPlay
                            if (lp != null) {
                                val accuser = s.players.firstOrNull { it.id == lp.playerId }?.name ?: "?"
                                Box(Modifier.clip(RoundedCornerShape(50)).background(Ub.Accent)
                                    .padding(horizontal = 12.dp, vertical = 5.dp)) {
                                    Text("$accuser claimed ${lp.count} × ${rankName(lp.claimedRank)}",
                                         fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Ub.OnAccent)
                                }
                            }
                            MonoLabel("Next expected · ${rankName(s.expectedRank)}", size = 9, color = Ub.Accent)
                        }
                        if (s.lastEvent.isNotEmpty()) MonoLabel(s.lastEvent, size = 10)
                        val reveal = s.lastReveal
                        if (reveal != null) {
                            Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel,
                                    fill = if (reveal.truthful) Ub.Surface else Ub.AccentSoft,
                                    stroke = if (reveal.truthful) Ub.Line else Ub.AccentLine)
                                .padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                val caller = s.players.firstOrNull { it.id == reveal.callerId }?.name ?: "?"
                                val accused = s.players.firstOrNull { it.id == reveal.accusedId }?.name ?: "?"
                                val loser = s.players.firstOrNull { it.id == reveal.loserId }?.name ?: "?"
                                MonoLabel(if (reveal.truthful) "Truthful claim" else "Caught cheating!",
                                          color = if (reveal.truthful) Ub.Online else Ub.Accent)
                                Text("$caller called BS on $accused · ${rankName(reveal.claimedRank)}",
                                     fontSize = 13.sp, color = Ub.Foreground)
                                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    for (c in reveal.cards) CardFace(c, small = true)
                                }
                                Text("$loser picks up the pile.", fontSize = 12.sp, color = Ub.Muted)
                            }
                        }
                        if (s.phase == "pendingWin") {
                            val w = s.players.firstOrNull { it.id == s.winnerId }
                            Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel).padding(16.dp),
                                   verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                MonoLabel("Pending win", color = Ub.Accent)
                                Text("${w?.name ?: "?"} played their last card claiming ${rankName(s.lastPlay?.claimedRank ?: 0)}.",
                                     fontSize = 13.sp, color = Ub.Foreground)
                                if (ctx.yourId != s.winnerId) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                        UbSecondaryButton("Call BS", modifier = Modifier.weight(1f),
                                            onClick = { ctx.client.send(JSONObject().put("type", "bs")) })
                                        UbPrimaryButton("Accept win", modifier = Modifier.weight(1f),
                                            onClick = { ctx.client.send(JSONObject().put("type", "accept_win")) })
                                    }
                                } else {
                                    Text("Wait for the others to call BS or accept.",
                                         fontSize = 12.sp, color = Ub.Muted)
                                }
                            }
                        }
                        MonoLabel("Your hand · ${s.hand.size}")
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
                                    .then(if (sel) Modifier.border(3.dp, Ub.Accent, RoundedCornerShape(8.dp))
                                          else Modifier)
                                ) { CardFace(c) }
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.fillMaxWidth()) {
                            val canBs = s.lastPlay != null && s.lastPlay!!.playerId != ctx.yourId && s.phase == "playing"
                            if (canBs) {
                                UbSecondaryButton("Call cheat ✋", modifier = Modifier.weight(1f),
                                    onClick = { ctx.client.send(JSONObject().put("type", "bs")) })
                            }
                            if (s.currentId == ctx.yourId && s.phase == "playing") {
                                UbPrimaryButton("Play ${selected.size} × ${rankName(s.expectedRank)}",
                                    modifier = Modifier.weight(1f), enabled = selected.isNotEmpty(),
                                    onClick = {
                                        val picked = s.hand.filter { selected.contains("${it.suit}-${it.rank}") }
                                        if (picked.isEmpty()) return@UbPrimaryButton
                                        val arr = JSONArray()
                                        for (c in picked) arr.put(JSONObject().put("suit", c.suit).put("rank", c.rank))
                                        ctx.client.send(JSONObject().put("type", "play")
                                            .put("claimedRank", s.expectedRank).put("cards", arr))
                                        selected.clear()
                                    })
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayerRow(name: String, host: Boolean, isYou: Boolean) {
    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
        .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Avatar(name, host = host, size = 30.dp)
        Spacer(Modifier.width(12.dp))
        Text(name, fontSize = 15.sp,
             fontWeight = if (isYou) FontWeight.Bold else FontWeight.SemiBold, color = Ub.Foreground)
        if (isYou) { Spacer(Modifier.width(8.dp)); MonoLabel("you", size = 9, color = Ub.Accent) }
        Spacer(Modifier.weight(1f))
        if (host) MonoLabel("host", size = 9, color = Ub.Faint)
    }
}

@Composable
private fun PlayerChip(name: String, host: Boolean, cards: Int, current: Boolean) {
    Row(
        Modifier.ubCard(radius = Ub.Radius.button,
            fill = if (current) Ub.AccentSoft else Ub.Surface,
            stroke = if (current) Ub.AccentLine else Ub.Line)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(name, host = host, size = 26.dp)
        Spacer(Modifier.width(8.dp))
        Column {
            Text(name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
            MonoLabel("$cards cards", size = 9, color = Ub.Faint)
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
