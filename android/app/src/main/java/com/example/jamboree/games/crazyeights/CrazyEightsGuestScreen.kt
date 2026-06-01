package com.example.jamboree.games.crazyeights

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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.ads.AdBanner
import com.example.jamboree.ads.AdBannerPlacement
import com.example.jamboree.ads.AdInterstitialController
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbSecondaryButton
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.theme.ubAccentCard
import com.example.jamboree.theme.ubCard
import com.example.jamboree.join.GuestContext
import com.example.jamboree.join.GuestSeriesState
import com.example.jamboree.join.GuestTutorialContent
import com.example.jamboree.join.GuestTutorialState
import com.example.jamboree.join.SeriesBannerCard
import com.example.jamboree.join.TutorialGuestCard
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
    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
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
                    MonoLabel("Crazy 8s · lobby", color = Ub.Accent)
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
                    MonoLabel("Crazy 8s", color = Ub.Accent)
                    val mine = s.currentId == ctx.yourId
                    Text(if (mine) "Your turn"
                         else "${s.players.firstOrNull { it.id == s.currentId }?.name ?: ""}'s turn",
                         fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.8).sp,
                         color = if (mine) Ub.Accent else Ub.Foreground)
                    Text("Match ${suitGlyph(s.activeSuit ?: s.topCard?.suit ?: "")} or rank — or play an 8.",
                         fontSize = 13.sp, color = Ub.Muted)
                }
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (p in s.players) PlayerChip(p.name, p.isHost, p.handCount, s.currentId == p.id)
                }
                Row(
                    Modifier.fillMaxWidth()
                        .clip(RoundedCornerShape(Ub.Radius.hero))
                        .background(Brush.radialGradient(
                            listOf(Ub.Accent.copy(alpha = 0.12f), Color.Transparent), radius = 420f))
                        .padding(vertical = 28.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally,
                           verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(contentAlignment = Alignment.Center) {
                            com.example.jamboree.games.cards.GridCardBack(width = 70.dp)
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("${s.drawCount}", fontSize = 22.sp,
                                     fontWeight = FontWeight.Bold, color = Color.White)
                                Text("draw", fontSize = 10.sp, color = Color.White.copy(alpha = 0.7f))
                            }
                        }
                        MonoLabel("Draw · ${s.drawCount}", size = 9)
                    }
                    Spacer(Modifier.width(26.dp))
                    Column(horizontalAlignment = Alignment.CenterHorizontally,
                           verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        val top = s.topCard
                        if (top != null) CardFace(top) else Spacer(Modifier.size(64.dp, 90.dp))
                        MonoLabel("Suit ${suitGlyph(s.activeSuit ?: s.topCard?.suit ?: "")}",
                                  size = 9, color = Ub.Accent)
                    }
                }
                if (s.lastEvent.isNotEmpty()) MonoLabel(s.lastEvent, size = 10)
                MonoLabel("Your hand · ${s.hand.size}")
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
                if (s.currentId == ctx.yourId) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (s.justDrew) {
                            UbSecondaryButton("Pass", modifier = Modifier.weight(1f),
                                onClick = { ctx.client.send(JSONObject().put("type", "pass")) })
                        }
                        UbSecondaryButton(if (s.justDrew) "Drew" else "Draw",
                            modifier = Modifier.weight(1f), enabled = !s.justDrew,
                            onClick = { ctx.client.send(JSONObject().put("type", "draw")) })
                    }
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
    suitPickFor?.let { card ->
        AlertDialog(onDismissRequest = { suitPickFor = null },
            containerColor = Ub.Surface,
            confirmButton = {},
            dismissButton = { TextButton(onClick = { suitPickFor = null }) {
                Text("Cancel", color = Ub.Muted) } },
            title = { MonoLabel("Choose the next suit", color = Ub.Accent) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (row in listOf(listOf("spades", "hearts"), listOf("diamonds", "clubs"))) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            for (suit in row) {
                                Box(
                                    Modifier.weight(1f).height(64.dp).ubAccentCard(radius = Ub.Radius.button)
                                        .clickable {
                                            ctx.client.send(JSONObject().put("type", "play")
                                                .put("suit", card.suit).put("rank", card.rank)
                                                .put("declaredSuit", suit))
                                            suitPickFor = null
                                        },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(suitGlyph(suit), fontSize = 32.sp,
                                         color = if (suit == "diamonds" || suit == "hearts") Ub.Accent else Color.White)
                                }
                            }
                        }
                    }
                }
            }
        )
    }
    }
}

@Composable
private fun PlayerRow(name: String, host: Boolean, isYou: Boolean) {
    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
        .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Avatar(name, host = host, size = 32.dp)
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
        Modifier
            .ubCard(radius = Ub.Radius.button,
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
private fun CardFace(c: CrazyEightsGuestState.Card) {
    val suit = com.example.jamboree.games.cards.CardSuit.fromWire(c.suit)
    if (suit != null) {
        com.example.jamboree.games.cards.NoirCardFace(
            rank = c.rank, suit = suit, width = 70.dp, wildAccent = true,
        )
    } else {
        com.example.jamboree.games.cards.GridCardBack(width = 70.dp)
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
    var series by mutableStateOf(GuestSeriesState())

    fun isPlayable(c: Card): Boolean {
        val top = topCard ?: return true
        if (c.rank == 8) return true
        val active = activeSuit ?: top.suit
        return c.suit == active || c.rank == top.rank
    }

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
