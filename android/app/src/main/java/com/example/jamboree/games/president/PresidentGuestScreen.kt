package com.example.jamboree.games.president

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
                            MonoLabel("President · lobby", color = Ub.Accent)
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
                    "swapping" -> SwapPhase(s, ctx, selected)
                    "gameOver" -> {
                        val sorted = s.players.sortedBy { if (it.finishOrder == 0) Int.MAX_VALUE else it.finishOrder }
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            MonoLabel("Round over", color = Ub.Accent)
                            Text("Final tiers", fontSize = 28.sp, fontWeight = FontWeight.ExtraBold,
                                 letterSpacing = (-0.8).sp, color = Ub.Foreground)
                        }
                        for (p in sorted) {
                            val isPres = p.rank == "president"
                            Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
                                .padding(horizontal = 14.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                Text(if (p.finishOrder == 0) "?" else p.finishOrder.toString(),
                                     fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Ub.Faint)
                                Spacer(Modifier.width(10.dp))
                                Avatar(p.name, host = p.isHost, size = 30.dp)
                                Spacer(Modifier.width(12.dp))
                                Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                                Spacer(Modifier.weight(1f))
                                Box(Modifier.clip(RoundedCornerShape(50))
                                    .background(if (isPres) Ub.Accent else Color.White.copy(alpha = 0.06f))
                                    .padding(horizontal = 10.dp, vertical = 5.dp)) {
                                    Text(rankLabel(p.rank), fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                         color = if (isPres) Ub.OnAccent else Ub.Muted)
                                }
                            }
                        }
                        Text("Waiting for the host to start the next round…", fontSize = 12.sp, color = Ub.Muted)
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
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        MonoLabel("President · round ${s.roundNumber}", color = Ub.Accent)
        Text(if (isMyTurn) "Your turn"
             else "${s.players.firstOrNull { it.id == s.currentId }?.name ?: ""}'s turn",
             fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.8).sp,
             color = if (isMyTurn) Ub.Accent else Ub.Foreground)
        Text(if (s.trick == null) (if (isMyTurn) "Your lead — play anything." else "Awaiting the lead.")
             else "Beat the open trick or pass.", fontSize = 13.sp, color = Ub.Muted)
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
                    when {
                        p.finished -> MonoLabel(rankLabel(p.rank), size = 9, color = Ub.Accent)
                        s.passed.contains(p.id) -> MonoLabel("passed", size = 9, color = Ub.Faint)
                        else -> MonoLabel("${p.handCount} cards", size = 9, color = Ub.Faint)
                    }
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
        MonoLabel(if (s.trick == null) "Open lead" else "To beat", size = 10, color = Ub.Accent)
        val t = s.trick
        if (t != null) {
            Text("${t.kind.replaceFirstChar { it.uppercase() }}${if (t.length > 0) " · ${t.length}" else ""}",
                 fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground)
            MonoLabel("Beat power ${t.topPower}", size = 9)
        } else {
            Text(if (isMyTurn) "Play anything" else "Awaiting lead",
                 fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground)
        }
        s.lastPlay?.let { lp ->
            val pname = s.players.firstOrNull { it.id == lp.playerId }?.name ?: "?"
            val cards = lp.cards.joinToString(" ") { rankShort(it.rank) + suitGlyph(it.suit) }
            Text("$pname: $cards", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Ub.Muted)
        }
    }
    if (s.lastEvent.isNotEmpty()) MonoLabel(s.lastEvent, size = 10)
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
            Box(Modifier
                .clickable { if (sel) selected.remove(key) else selected.add(key) }
                .then(if (sel) Modifier.border(3.dp, Ub.Accent, RoundedCornerShape(8.dp))
                      else Modifier)) { CardFace(c) }
        }
    }
    if (isMyTurn) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxWidth()) {
            if (s.trick != null) {
                UbSecondaryButton("Pass", modifier = Modifier.weight(1f),
                    onClick = { ctx.client.send(JSONObject().put("type", "pass")); selected.clear() })
            }
            UbPrimaryButton("Play ${selected.size}", modifier = Modifier.weight(1f),
                enabled = selected.isNotEmpty(),
                onClick = {
                    val picked = s.hand.filter { selected.contains("${it.suit}-${it.rank}") }
                    if (picked.isEmpty()) return@UbPrimaryButton
                    val arr = JSONArray()
                    for (c in picked) arr.put(JSONObject().put("suit", c.suit).put("rank", c.rank))
                    ctx.client.send(JSONObject().put("type", "play").put("cards", arr))
                    selected.clear()
                })
        }
    }
}

@Composable
private fun SwapPhase(s: PresidentGuestState, ctx: GuestContext, selected: SnapshotStateListOfString) {
    MonoLabel("Round ${s.roundNumber} · swap", color = Ub.Accent)
    if (s.swapPrompts.isEmpty()) {
        Text("Waiting for others to swap cards…", fontSize = 13.sp, color = Ub.Muted)
        return
    }
    for (p in s.swapPrompts) {
        Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel).padding(16.dp),
               verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (p.giverChooses) {
                Text("Give ${p.count} card${if (p.count == 1) "" else "s"} of your choice to ${p.toName}",
                     fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Ub.Foreground)
                Text("Pick ${p.count} below, then send.", fontSize = 12.sp, color = Ub.Muted)
                UbPrimaryButton("Send ${selected.size}/${p.count} → ${p.toName}",
                    enabled = selected.size == p.count,
                    onClick = {
                        val picked = s.hand.filter { selected.contains("${it.suit}-${it.rank}") }
                        val arr = JSONArray()
                        for (c in picked) arr.put(JSONObject().put("suit", c.suit).put("rank", c.rank))
                        ctx.client.send(JSONObject().put("type", "swap").put("cards", arr))
                        selected.clear()
                    })
            } else {
                Text("Auto-sending your top ${p.count} card${if (p.count == 1) "" else "s"} to ${p.toName}",
                     fontSize = 14.sp, color = Ub.Foreground)
                UbPrimaryButton("Send best ${p.count} → ${p.toName}",
                    onClick = { ctx.client.send(JSONObject().put("type", "swap").put("cards", JSONArray())) })
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
            Box(Modifier
                .clickable { if (sel) selected.remove(key) else selected.add(key) }
                .then(if (sel) Modifier.border(3.dp, Ub.Accent, RoundedCornerShape(8.dp))
                      else Modifier)) { CardFace(c) }
        }
    }
}

@Composable
private fun CardFace(c: PresidentGuestState.Card) {
    val suit = com.example.jamboree.games.cards.CardSuit.fromWire(c.suit)
    if (suit != null) {
        com.example.jamboree.games.cards.NoirCardFace(rank = c.rank, suit = suit, width = 70.dp)
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
