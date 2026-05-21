package com.example.ubapp.games.bluffmarket

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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
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
                when (s.phase) {
                    "lobby" -> {
                        TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                            onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                            onVote = { yes -> s.myTutorialVote = yes
                                ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                        Text("Players (${s.players.size})", style = MaterialTheme.typography.titleSmall)
                        for (p in s.players) Text(p.name + if (p.isHost) " (host)" else "")
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
                Text("${p.handCount}c · ${p.coins}\$",
                     style = MaterialTheme.typography.labelSmall,
                     color = if (isCurrent) Color.White else Color(0xFFA0A8B0))
                Text("turn ${p.turnsTaken}/${s.turnsPerPlayer}",
                     style = MaterialTheme.typography.labelSmall,
                     color = if (isCurrent) Color.White else Color(0xFFA0A8B0))
                if (!p.guaranteeUsed) Text("Guar",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = Color(0xFFFACC15))
            }
        }
    }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Market: ${s.marketSize} card${if (s.marketSize == 1) "" else "s"} face down",
                 style = MaterialTheme.typography.bodyMedium)
            Text(if (isMyTurn) "Your turn — Trade, Buy, or Sell"
                 else "${s.players.firstOrNull { it.id == s.currentId }?.name ?: ""}'s turn",
                 style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold,
                 color = if (isMyTurn) Color(0xFF7BD389) else Color(0xFFA0A8B0))
            if (s.lastEvent.isNotEmpty())
                Text(s.lastEvent, style = MaterialTheme.typography.bodySmall)
        }
    }

    s.trade?.let { TradeCard(s, ctx, it, selectedId) { setSelected(null) } }

    Text("Your hand (${s.hand.size})", style = MaterialTheme.typography.titleSmall)
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
                .then(if (sel) Modifier.border(3.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(8.dp))
                      else Modifier)) { BluffCardFace(c) }
        }
    }

    if (s.trade == null && isMyTurn && s.phase == "playing") {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                enabled = s.marketSize > 0,
                onClick = { ctx.client.send(JSONObject().put("type", "buy")) },
                modifier = Modifier.weight(1f),
            ) { Text("Buy market") }
            OutlinedButton(
                enabled = selectedId != null,
                onClick = {
                    selectedId?.let {
                        ctx.client.send(JSONObject().put("type", "sell").put("cardId", it))
                    }
                    setSelected(null)
                },
                modifier = Modifier.weight(1f),
            ) { Text("Sell selected (+2)") }
        }
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Propose trade (offer selected)", style = MaterialTheme.typography.titleSmall)
                val candidates = s.players.filter { it.id != ctx.yourId }
                for (p in candidates) {
                    OutlinedButton(
                        enabled = selectedId != null,
                        onClick = {
                            selectedId?.let {
                                ctx.client.send(JSONObject().put("type", "propose_trade")
                                    .put("targetId", p.id).put("cardId", it))
                            }
                            setSelected(null)
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Trade with ${p.name}") }
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

    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Trade: $proposerName ↔ $targetName",
                 style = MaterialTheme.typography.titleSmall)
            if (t.revealed) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(proposerName, style = MaterialTheme.typography.bodySmall)
                        t.proposerCard?.let { BluffCardFace(it) }
                    }
                    Text("⇄", style = MaterialTheme.typography.headlineMedium)
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(targetName, style = MaterialTheme.typography.bodySmall)
                        t.targetCard?.let { BluffCardFace(it) }
                    }
                }
                if (imParty) {
                    val answered = if (imProposer) t.proposerAccept != null else t.targetAccept != null
                    if (answered) {
                        Text("You answered. Waiting for the other side…",
                             style = MaterialTheme.typography.bodySmall)
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { ctx.client.send(JSONObject().put("type", "respond_trade").put("accept", true)) },
                                   modifier = Modifier.weight(1f),
                                   colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)),
                            ) { Text("Accept") }
                            Button(onClick = { ctx.client.send(JSONObject().put("type", "respond_trade").put("accept", false)) },
                                   modifier = Modifier.weight(1f),
                                   colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828)),
                            ) { Text("Reject") }
                            if (!myGuar) {
                                OutlinedButton(onClick = { ctx.client.send(JSONObject().put("type", "guarantee")) },
                                               modifier = Modifier.weight(1f)) { Text("Guarantee") }
                            }
                        }
                    }
                }
            } else {
                if (imTarget) {
                    Text("$proposerName is proposing a trade. Commit a card to counter.",
                         style = MaterialTheme.typography.bodySmall)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            enabled = selectedId != null,
                            onClick = {
                                selectedId?.let {
                                    ctx.client.send(JSONObject().put("type", "counter_trade").put("cardId", it))
                                }
                                clearSelected()
                            },
                            modifier = Modifier.weight(1f),
                        ) { Text("Commit selected") }
                        OutlinedButton(
                            onClick = { ctx.client.send(JSONObject().put("type", "decline_trade")) },
                            modifier = Modifier.weight(1f),
                        ) { Text("Decline") }
                    }
                } else {
                    Text("$proposerName committed. Waiting for $targetName to counter…",
                         style = MaterialTheme.typography.bodySmall)
                    if (imProposer) {
                        OutlinedButton(onClick = { ctx.client.send(JSONObject().put("type", "decline_trade")) })
                        { Text("Cancel proposal") }
                    }
                }
            }
            if (t.proposerGuarantee || t.targetGuarantee) {
                Text("Guarantee invoked — trade will be forced.",
                     style = MaterialTheme.typography.bodySmall, color = Color(0xFFFACC15))
            }
        }
    }
}

@Composable
private fun ScoringPhase(s: BluffMarketGuestState, finalized: Boolean) {
    val sorted = s.scoreRows.sortedByDescending { it.total }
    Text(if (finalized) "Game over" else "Final scores — pending host reveal",
         style = MaterialTheme.typography.headlineSmall)
    if (finalized) {
        val winner = sorted.firstOrNull { it.id == s.winnerId } ?: sorted.firstOrNull()
        winner?.let {
            Text("${it.name} wins!", style = MaterialTheme.typography.titleLarge)
        }
    }
    for (r in sorted) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(r.name + (if (r.hasBomb) " 💣" else "") + (if (r.id == s.winnerId) " 🏆" else ""))
            Text("${r.total}  (sum ${r.sum} + coins ${r.coins})",
                 style = MaterialTheme.typography.bodySmall)
        }
    }
    if (!finalized) Text("Waiting for the host…",
                          style = MaterialTheme.typography.bodySmall,
                          color = Color(0xFFA0A8B0))
}

@Composable
private fun BluffCardFace(c: BluffMarketGuestState.Card) {
    when (c.kind) {
        "bomb" -> com.example.ubapp.games.cards.BluffBombCard(width = 80.dp)
        "wildcard" -> com.example.ubapp.games.cards.BluffPointCard(value = 0, width = 80.dp)
        else -> com.example.ubapp.games.cards.BluffPointCard(value = c.value, width = 80.dp)
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

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
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
