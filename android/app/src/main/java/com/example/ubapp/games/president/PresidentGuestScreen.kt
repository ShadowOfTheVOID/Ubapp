package com.example.ubapp.games.president

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
import com.example.ubapp.join.GuestSeriesState
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.SeriesBannerCard
import com.example.ubapp.join.TutorialGuestCard
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun PresidentGuestScreen(ctx: GuestContext) {
    val s = remember { PresidentGuestState() }
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
                    "swapping" -> SwapPhase(s, ctx, selected)
                    "gameOver" -> {
                        val sorted = s.players.sortedBy { if (it.finishOrder == 0) Int.MAX_VALUE else it.finishOrder }
                        Text("Round over", style = MaterialTheme.typography.headlineSmall)
                        for (p in sorted) Row(Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("${if (p.finishOrder == 0) "?" else p.finishOrder.toString()}. ${p.name}")
                            Text(rankLabel(p.rank), color = Color(0xFFFACC15))
                        }
                        Text("Waiting for the host to start the next round…",
                             style = MaterialTheme.typography.bodySmall)
                    }
                    else -> TablePhase(s, ctx, selected)
                }
            }
        }
    }
}

@Composable
private fun TablePhase(s: PresidentGuestState, ctx: GuestContext, selected: SnapshotStateListOfString) {
    val isMyTurn = s.currentId == ctx.yourId
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (p in s.players) {
            val isCurrent = s.currentId == p.id
            val passed = s.passed.contains(p.id)
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
                if (p.finished) Text(rankLabel(p.rank),
                                     style = MaterialTheme.typography.labelSmall,
                                     color = Color(0xFFFACC15))
                else if (passed) Text("passed",
                                      style = MaterialTheme.typography.labelSmall,
                                      color = Color(0xFFA0A8B0))
            }
        }
    }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp),
               horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Round ${s.roundNumber}", style = MaterialTheme.typography.bodySmall)
            val t = s.trick
            if (t != null) {
                Text("Open trick: ${t.kind}${if (t.length > 0) " (${t.length})" else ""}",
                     style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Text("Must beat power ${t.topPower}", style = MaterialTheme.typography.bodySmall)
            } else {
                Text(if (isMyTurn) "Your lead — play anything" else "Awaiting lead",
                     style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            }
            s.lastPlay?.let { lp ->
                val pname = s.players.firstOrNull { it.id == lp.playerId }?.name ?: "?"
                val cards = lp.cards.joinToString(" ") { rankShort(it.rank) + suitGlyph(it.suit) }
                Text("Last: $pname — $cards", style = MaterialTheme.typography.bodySmall)
            }
            if (s.lastEvent.isNotEmpty())
                Text(s.lastEvent, style = MaterialTheme.typography.bodySmall)
        }
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
            Box(Modifier
                .clickable { if (sel) selected.remove(key) else selected.add(key) }
                .then(if (sel) Modifier.border(3.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(8.dp))
                      else Modifier)) { CardFace(c) }
        }
    }
    if (isMyTurn) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()) {
            Button(
                enabled = selected.isNotEmpty(),
                onClick = {
                    val picked = s.hand.filter { selected.contains("${it.suit}-${it.rank}") }
                    if (picked.isEmpty()) return@Button
                    val arr = JSONArray()
                    for (c in picked) arr.put(JSONObject().put("suit", c.suit).put("rank", c.rank))
                    ctx.client.send(JSONObject().put("type", "play").put("cards", arr))
                    selected.clear()
                },
                modifier = Modifier.weight(1f),
            ) { Text("Play ${selected.size}") }
            if (s.trick != null) {
                OutlinedButton(
                    onClick = { ctx.client.send(JSONObject().put("type", "pass")); selected.clear() },
                    modifier = Modifier.weight(1f),
                ) { Text("Pass") }
            }
        }
    }
}

@Composable
private fun SwapPhase(s: PresidentGuestState, ctx: GuestContext, selected: SnapshotStateListOfString) {
    if (s.swapPrompts.isEmpty()) {
        Text("Waiting for others to swap cards…", style = MaterialTheme.typography.bodyMedium)
        return
    }
    for (p in s.swapPrompts) {
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (p.giverChooses) {
                    Text("Give ${p.count} card${if (p.count == 1) "" else "s"} to ${p.toName}",
                         style = MaterialTheme.typography.titleSmall)
                    Text("Pick ${p.count} below, then tap Send.", style = MaterialTheme.typography.bodySmall)
                    Button(
                        enabled = selected.size == p.count,
                        onClick = {
                            val picked = s.hand.filter { selected.contains("${it.suit}-${it.rank}") }
                            val arr = JSONArray()
                            for (c in picked) arr.put(JSONObject().put("suit", c.suit).put("rank", c.rank))
                            ctx.client.send(JSONObject().put("type", "swap").put("cards", arr))
                            selected.clear()
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Send ${selected.size}/${p.count} → ${p.toName}") }
                } else {
                    Text("Auto-send your top ${p.count} card${if (p.count == 1) "" else "s"} to ${p.toName}.",
                         style = MaterialTheme.typography.titleSmall)
                    Button(
                        onClick = { ctx.client.send(JSONObject().put("type", "swap").put("cards", JSONArray())) },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Send best ${p.count} → ${p.toName}") }
                }
            }
        }
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
            Box(Modifier
                .clickable { if (sel) selected.remove(key) else selected.add(key) }
                .then(if (sel) Modifier.border(3.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(8.dp))
                      else Modifier)) { CardFace(c) }
        }
    }
}

@Composable
private fun CardFace(c: PresidentGuestState.Card) {
    val suit = com.example.ubapp.games.cards.CardSuit.fromWire(c.suit)
    if (suit != null) {
        com.example.ubapp.games.cards.NoirCardFace(rank = c.rank, suit = suit, width = 70.dp)
    } else {
        com.example.ubapp.games.cards.GridCardBack(width = 70.dp)
    }
}

private fun suitGlyph(s: String): String = when (s) {
    "clubs" -> "♣"; "diamonds" -> "♦"; "hearts" -> "♥"; "spades" -> "♠"; else -> ""
}
private fun rankShort(r: Int): String = when (r) {
    11 -> "J"; 12 -> "Q"; 13 -> "K"; 14 -> "A"; else -> r.toString()
}
private fun rankLabel(r: String): String = when (r) {
    "president" -> "President"; "vicePresident" -> "VP"
    "viceScum" -> "Vice Scum"; "scum" -> "Scum"; else -> ""
}

private typealias SnapshotStateListOfString = androidx.compose.runtime.snapshots.SnapshotStateList<String>

class PresidentGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean, val handCount: Int,
                      val rank: String, val finished: Boolean, val finishOrder: Int)
    data class Card(val suit: String, val rank: Int)
    data class TrickInfo(val kind: String, val length: Int, val topPower: Int, val leaderId: String)
    data class LastPlay(val playerId: String, val cards: List<Card>)
    data class SwapPrompt(val toId: String, val toName: String, val count: Int, val giverChooses: Boolean)

    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var hand by mutableStateOf<List<Card>>(emptyList())
    var trick by mutableStateOf<TrickInfo?>(null)
    var lastPlay by mutableStateOf<LastPlay?>(null)
    var currentId by mutableStateOf<String?>(null)
    var lastEvent by mutableStateOf("")
    var roundNumber by mutableIntStateOf(0)
    var swapPrompts by mutableStateOf<List<SwapPrompt>>(emptyList())
    var passed by mutableStateOf<Set<String>>(emptySet())
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
                           o.optBoolean("isHost"), 0, "neutral", false, 0)
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
                           o.optString("rank", "neutral"),
                           o.optBoolean("finished", false),
                           o.optInt("finishOrder", 0))
                }
                currentId = m.optString("currentId").ifEmpty { null }
                lastEvent = m.optString("lastEvent", "")
                roundNumber = m.optInt("roundNumber", roundNumber)
                val t = m.optJSONObject("trick")
                trick = t?.let { TrickInfo(it.optString("kind"), it.optInt("length", 0),
                                           it.optInt("topPower", 0), it.optString("leaderId")) }
                val lp = m.optJSONObject("lastPlay")
                lastPlay = lp?.let {
                    val cs = it.optJSONArray("cards")
                    val cards = if (cs == null) emptyList()
                                else (0 until cs.length()).map { i ->
                                    val o = cs.getJSONObject(i)
                                    Card(o.optString("suit"), o.optInt("rank"))
                                }
                    LastPlay(it.optString("playerId"), cards)
                }
                val pa = m.optJSONArray("passedThisTrick")
                passed = if (pa == null) emptySet()
                         else (0 until pa.length()).map { pa.getString(it) }.toSet()
            }
            "hand" -> {
                val arr = m.optJSONArray("cards") ?: return
                hand = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Card(o.optString("suit"), o.optInt("rank"))
                }
            }
            "swap_prompts" -> {
                val arr = m.optJSONArray("prompts") ?: JSONArray()
                swapPrompts = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    SwapPrompt(o.optString("toId"), o.optString("toName"),
                               o.optInt("count"), o.optBoolean("giverChooses"))
                }
            }
            "over" -> {
                phase = "gameOver"
                val arr = m.optJSONArray("rankings")
                if (arr != null) {
                    val rows = (0 until arr.length()).associateBy { i -> arr.getJSONObject(i).optString("id") }
                    players = players.map { existing ->
                        val idx = rows[existing.id]
                        if (idx == null) existing
                        else {
                            val row = arr.getJSONObject(idx)
                            existing.copy(
                                rank = row.optString("rank", existing.rank),
                                finished = true,
                                finishOrder = row.optInt("finishOrder", existing.finishOrder),
                            )
                        }
                    }
                }
            }
            "reset" -> {
                phase = "lobby"; hand = emptyList(); trick = null; lastPlay = null
                passed = emptySet(); swapPrompts = emptyList(); lastEvent = ""; roundNumber = 0
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
}
