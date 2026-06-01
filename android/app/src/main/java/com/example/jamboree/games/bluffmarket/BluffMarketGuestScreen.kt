package com.example.jamboree.games.bluffmarket

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
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.LobbyPlayerRow
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
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun BluffMarketGuestScreen(ctx: GuestContext) {
    val s = remember { BluffMarketGuestState() }
    var tick by remember { mutableIntStateOf(0) }
    var selectedId by remember { mutableStateOf<String?>(null) }
    DisposableEffect(ctx) {
        ctx.client.onMessage = { msg -> s.handle(msg); tick++ }
        for (m in ctx.replay) s.handle(m)
        onDispose { ctx.client.onMessage = null }
    }
    @Suppress("UNUSED_EXPRESSION") tick

    JamboreeTheme {
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
                            MonoLabel("Bluff Market · lobby", color = Ub.Accent)
                            Text("Waiting for the deal", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
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
                    "scoring" -> ScoringPhase(s, finalized = false)
                    "gameOver" -> ScoringPhase(s, finalized = true)
                    else -> TablePhase(s, ctx, selectedId) { selectedId = it }
                }
            }
        }
    }
}

@Composable
private fun TablePhase(
    s: BluffMarketGuestState,
    ctx: GuestContext,
    selectedId: String?,
    setSelected: (String?) -> Unit,
) {
    val isMyTurn = s.currentId == ctx.yourId
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        MonoLabel("Bluff Market", color = Ub.Accent)
        Text(if (isMyTurn && s.phase == "playing") "Your turn"
             else "${s.players.firstOrNull { it.id == s.currentId }?.name ?: ""}'s turn",
             fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.8).sp,
             color = if (isMyTurn && s.phase == "playing") Ub.Accent else Ub.Foreground)
        Text("Trade face-down, buy, or sell. One bomb is worth −25.",
             fontSize = 13.sp, color = Ub.Muted)
    }
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (p in s.players) {
            val isCurrent = s.currentId == p.id
            Row(Modifier.ubCard(radius = Ub.Radius.button,
                    fill = if (isCurrent) Ub.AccentSoft else Ub.Surface,
                    stroke = if (isCurrent) Ub.AccentLine else Ub.Line)
                .padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Avatar(p.name, host = p.isHost, size = 26.dp)
                Spacer(Modifier.width(8.dp))
                Column {
                    Text(p.name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                    MonoLabel("${p.handCount}c·${p.coins}¢", size = 9, color = Ub.Faint)
                    if (!p.guaranteeUsed) MonoLabel("guar", size = 8, color = Ub.Accent)
                }
            }
        }
    }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Ub.Radius.hero))
            .background(Brush.radialGradient(
                listOf(Ub.Accent.copy(alpha = 0.12f), Color.Transparent), radius = 420f))
            .padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (s.marketSize > 0) {
            Box(Modifier.size(96.dp, 108.dp), contentAlignment = Alignment.Center) {
                for (i in 0 until minOf(s.marketSize, 4)) {
                    Box(Modifier.offset(x = (i * 1.5f).dp, y = (i * 1.5f).dp)) {
                        com.example.jamboree.games.cards.GridCardBack(width = 70.dp)
                    }
                }
            }
        }
        MonoLabel("Market · ${s.marketSize} face down", size = 10)
    }
    if (s.lastEvent.isNotEmpty()) MonoLabel(s.lastEvent, size = 10)

    s.trade?.let { TradeCard(s, ctx, it, selectedId) { setSelected(null) } }

    MonoLabel("Your hand · ${s.hand.size}")
    LazyVerticalGrid(
        columns = GridCells.Adaptive(86.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.heightIn(max = 320.dp),
    ) {
        items(s.hand) { c ->
            val sel = selectedId == c.id
            Box(Modifier
                .clickable { setSelected(if (sel) null else c.id) }
                .then(if (sel) Modifier.border(3.dp, Ub.Accent, RoundedCornerShape(8.dp))
                      else Modifier)) { BluffCardFace(c) }
        }
    }

    if (s.trade == null && isMyTurn && s.phase == "playing") {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            UbSecondaryButton("Buy market", modifier = Modifier.weight(1f), enabled = s.marketSize > 0,
                onClick = { ctx.client.send(JSONObject().put("type", "buy")) })
            UbSecondaryButton("Sell selected (+2)", modifier = Modifier.weight(1f), enabled = selectedId != null,
                onClick = {
                    selectedId?.let { ctx.client.send(JSONObject().put("type", "sell").put("cardId", it)) }
                    setSelected(null)
                })
        }
        val candidates = s.players.filter { it.id != ctx.yourId }
        if (s.hand.isNotEmpty() && candidates.isNotEmpty()) {
            Column(Modifier.fillMaxWidth().ubCard().padding(14.dp),
                   verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MonoLabel("Propose trade")
                for (p in candidates) {
                    UbSecondaryButton("Trade with ${p.name} — offer selected", enabled = selectedId != null,
                        onClick = {
                            selectedId?.let {
                                ctx.client.send(JSONObject().put("type", "propose_trade")
                                    .put("targetId", p.id).put("cardId", it))
                            }
                            setSelected(null)
                        })
                }
            }
        }
    }
}

@Composable
private fun TradeCard(
    s: BluffMarketGuestState,
    ctx: GuestContext,
    t: BluffMarketGuestState.Trade,
    selectedId: String?,
    clearSelected: () -> Unit,
) {
    val imProposer = ctx.yourId == t.proposerId
    val imTarget = ctx.yourId == t.targetId
    val imParty = imProposer || imTarget
    val proposerName = s.players.firstOrNull { it.id == t.proposerId }?.name ?: "?"
    val targetName = s.players.firstOrNull { it.id == t.targetId }?.name ?: "?"
    val myGuar = s.players.firstOrNull { it.id == ctx.yourId }?.guaranteeUsed == true

    Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel,
            fill = Ub.AccentSoft, stroke = Ub.AccentLine).padding(16.dp),
           verticalArrangement = Arrangement.spacedBy(10.dp),
           horizontalAlignment = Alignment.CenterHorizontally) {
        MonoLabel("Trade · $proposerName ↔ $targetName", color = Ub.Accent)
        if (t.revealed) {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    MonoLabel(proposerName, size = 9)
                    t.proposerCard?.let { BluffCardFace(it) }
                }
                Text("⇄", fontSize = 28.sp, color = Ub.Muted)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    MonoLabel(targetName, size = 9)
                    t.targetCard?.let { BluffCardFace(it) }
                }
            }
            if (imParty) {
                val answered = if (imProposer) t.proposerAccept != null else t.targetAccept != null
                if (answered) {
                    Text("You answered. Waiting for the other side…", fontSize = 12.sp, color = Ub.Muted)
                } else {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        UbPrimaryButton("Accept", modifier = Modifier.weight(1f),
                            onClick = { ctx.client.send(JSONObject().put("type", "respond_trade").put("accept", true)) })
                        UbSecondaryButton("Reject", modifier = Modifier.weight(1f),
                            onClick = { ctx.client.send(JSONObject().put("type", "respond_trade").put("accept", false)) })
                    }
                    if (!myGuar) {
                        UbSecondaryButton("Guarantee the trade",
                            onClick = { ctx.client.send(JSONObject().put("type", "guarantee")) })
                    }
                }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    MonoLabel(proposerName, size = 9)
                    Box(Modifier.alpha(if (t.proposerCommitted) 1f else 0.3f)) {
                        com.example.jamboree.games.cards.GridCardBack(width = 70.dp)
                    }
                }
                Text("?", fontSize = 28.sp, color = Ub.Muted)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    MonoLabel(targetName, size = 9)
                    Box(Modifier.alpha(if (t.targetCommitted) 1f else 0.3f)) {
                        com.example.jamboree.games.cards.GridCardBack(width = 70.dp)
                    }
                }
            }
            if (imTarget) {
                Text("$proposerName is proposing a trade. Commit a card to counter.",
                     fontSize = 12.sp, color = Ub.Foreground)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    UbPrimaryButton("Commit selected", modifier = Modifier.weight(1f), enabled = selectedId != null,
                        onClick = {
                            selectedId?.let { ctx.client.send(JSONObject().put("type", "counter_trade").put("cardId", it)) }
                            clearSelected()
                        })
                    UbSecondaryButton("Decline", modifier = Modifier.weight(1f),
                        onClick = { ctx.client.send(JSONObject().put("type", "decline_trade")) })
                }
            } else {
                Text("$proposerName committed. Waiting for $targetName to counter…",
                     fontSize = 12.sp, color = Ub.Muted)
                if (imProposer) {
                    UbSecondaryButton("Cancel proposal",
                        onClick = { ctx.client.send(JSONObject().put("type", "decline_trade")) })
                }
            }
        }
        if (t.proposerGuarantee || t.targetGuarantee) {
            MonoLabel("Guarantee invoked — trade forced", size = 9, color = Ub.Accent)
        }
    }
}

@Composable
private fun ScoringPhase(s: BluffMarketGuestState, finalized: Boolean) {
    val sorted = s.scoreRows.sortedByDescending { it.total }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MonoLabel(if (finalized) "Game over" else "Final scores · pending host reveal", color = Ub.Accent)
        if (finalized) {
            val winner = sorted.firstOrNull { it.id == s.winnerId } ?: sorted.firstOrNull()
            Text("${winner?.name ?: "?"} wins", fontSize = 28.sp, fontWeight = FontWeight.ExtraBold,
                 letterSpacing = (-0.8).sp, color = Ub.Foreground)
        }
    }
    for (r in sorted) {
        Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
            .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Avatar(r.name, size = 30.dp)
            Spacer(Modifier.width(12.dp))
            Column {
                Text(r.name + (if (r.id == s.winnerId) " 🏆" else "") + (if (r.hasBomb) " 💣" else ""),
                     fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                MonoLabel("sum ${r.sum} + coins ${r.coins}", size = 9, color = Ub.Faint)
            }
            Spacer(Modifier.weight(1f))
            Text("${r.total}", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = Ub.Foreground)
        }
    }
    if (!finalized) Text("Waiting for the host…", fontSize = 12.sp, color = Ub.Muted)
}

@Composable
private fun BluffCardFace(c: BluffMarketGuestState.Card) {
    when (c.kind) {
        "bomb" -> com.example.jamboree.games.cards.BluffBombCard(width = 80.dp)
        "wildcard" -> com.example.jamboree.games.cards.BluffPointCard(value = 0, width = 80.dp)
        else -> com.example.jamboree.games.cards.BluffPointCard(value = c.value, width = 80.dp)
    }
}

class BluffMarketGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean,
                      val handCount: Int, val coins: Int, val turnsTaken: Int,
                      val guaranteeUsed: Boolean)
    data class Card(val id: String, val kind: String, val value: Int, val label: String)
    data class Trade(
        val proposerId: String, val targetId: String,
        val proposerCommitted: Boolean, val targetCommitted: Boolean,
        val revealed: Boolean,
        val proposerGuarantee: Boolean, val targetGuarantee: Boolean,
        val proposerAccept: Boolean?, val targetAccept: Boolean?,
        val proposerCard: Card?, val targetCard: Card?,
    )
    data class ScoreRow(val id: String, val name: String, val total: Int,
                        val sum: Int, val coins: Int, val hasBomb: Boolean)

    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var hand by mutableStateOf<List<Card>>(emptyList())
    var marketSize by mutableIntStateOf(0)
    var currentId by mutableStateOf<String?>(null)
    var trade by mutableStateOf<Trade?>(null)
    var lastEvent by mutableStateOf("")
    var turnsPerPlayer by mutableIntStateOf(5)
    var scoreRows by mutableStateOf<List<ScoreRow>>(emptyList())
    var winnerId by mutableStateOf<String?>(null)
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
                           o.optBoolean("isHost"), 0, 0, 0, false)
                }
                phase = "lobby"
            }
            "state" -> {
                phase = m.optString("phase", phase)
                val arr = m.optJSONArray("players")
                if (arr != null) players = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"),
                           false,
                           o.optInt("handCount", 0),
                           o.optInt("coins", 0),
                           o.optInt("turnsTaken", 0),
                           o.optBoolean("guaranteeUsed", false))
                }
                marketSize = m.optInt("marketSize", marketSize)
                currentId = m.optString("currentId").ifEmpty { null }
                lastEvent = m.optString("lastEvent", "")
                turnsPerPlayer = m.optInt("turnsPerPlayer", turnsPerPlayer)
                val t = m.optJSONObject("trade")
                trade = t?.let {
                    Trade(
                        it.optString("proposerId"),
                        it.optString("targetId"),
                        it.optBoolean("proposerCommitted", false),
                        it.optBoolean("targetCommitted", false),
                        it.optBoolean("revealed", false),
                        it.optBoolean("proposerGuarantee", false),
                        it.optBoolean("targetGuarantee", false),
                        if (it.has("proposerAccept")) it.optBoolean("proposerAccept") else null,
                        if (it.has("targetAccept")) it.optBoolean("targetAccept") else null,
                        it.optJSONObject("proposerCard")?.let(::parseCard),
                        it.optJSONObject("targetCard")?.let(::parseCard),
                    )
                }
            }
            "hand" -> {
                val arr = m.optJSONArray("cards") ?: return
                hand = (0 until arr.length()).map { parseCard(arr.getJSONObject(it)) }
            }
            "scores" -> scoreRows = parseRows(m.optJSONArray("rows"))
            "over" -> {
                phase = "gameOver"
                winnerId = m.optString("winnerId").ifEmpty { null }
                scoreRows = parseRows(m.optJSONArray("rows"))
            }
            "reset" -> {
                phase = "lobby"; hand = emptyList(); trade = null; marketSize = 0
                scoreRows = emptyList(); winnerId = null; lastEvent = ""
            }
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

    private fun parseCard(o: JSONObject): Card =
        Card(o.optString("id"), o.optString("kind", "points"),
             o.optInt("value", 0), o.optString("label"))

    private fun parseRows(arr: JSONArray?): List<ScoreRow> {
        if (arr == null) return emptyList()
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            ScoreRow(o.optString("id"), o.optString("name"),
                     o.optInt("total"), o.optInt("sum"),
                     o.optInt("coins"), o.optBoolean("hasBomb"))
        }
    }
}
