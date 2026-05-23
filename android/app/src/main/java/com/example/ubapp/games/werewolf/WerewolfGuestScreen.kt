package com.example.ubapp.games.werewolf

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.theme.Avatar
import com.example.ubapp.theme.MonoLabel
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.UbPrimaryButton
import com.example.ubapp.theme.UbappTheme
import com.example.ubapp.theme.ubCard
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
import org.json.JSONObject

@Composable
fun WerewolfGuestScreen(ctx: GuestContext) {
    val s = remember { WerewolfGuestState() }
    var tick by remember { mutableIntStateOf(0) }
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
        val iAmAlive = s.alive.any { it.id == ctx.yourId }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MonoLabel(phaseLabel(s), color = Ub.Accent)
            Spacer(Modifier.weight(1f))
            if (s.phase != "lobby")
                MonoLabel(if (iAmAlive) "alive" else "out", size = 9,
                          color = if (iAmAlive) Ub.Online else Ub.Faint)
        }
        if (s.error != null) InfoBanner(s.error!!, accent = true)
        when (s.phase) {
            "lobby" -> {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Waiting for the host", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
                         letterSpacing = (-0.8).sp, color = Ub.Foreground)
                    Text("Playing as ${ctx.yourName}", fontSize = 13.sp, color = Ub.Muted)
                }
                TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                    onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                    onVote = { yes -> s.myTutorialVote = yes
                        ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                MonoLabel("In the room · ${s.lobby.size}")
                for (p in s.lobby) PlayerRow(p.name, p.isHost, p.id == ctx.yourId)
            }
            "night" -> {
                RoleCard(s, ctx.yourId)
                if (!iAmAlive) InfoBanner("You're out — watching from the sidelines.")
                else when (s.role) {
                    "werewolf" -> TargetPicker(s, "Choose a victim",
                        s.alive.filter { it.id != ctx.yourId && it.id !in s.wolfIds }, "night", "Lock in kill", false, ctx)
                    "seer" -> TargetPicker(s, "Investigate a player",
                        s.alive.filter { it.id != ctx.yourId }, "night", "Investigate", false, ctx)
                    else -> InfoBanner("The wolves and the seer are acting in the dark…")
                }
                SeerFindings(s)
            }
            "dayReveal" -> { RoleCard(s, ctx.yourId); LastNight(s); SeerFindings(s) }
            "dayVote" -> {
                RoleCard(s, ctx.yourId); LastNight(s); SeerFindings(s)
                if (!iAmAlive) InfoBanner("You're out — watching from the sidelines.")
                else TargetPicker(s, "Vote to lynch",
                                  s.alive.filter { it.id != ctx.yourId }, "vote", "Lock in vote", true, ctx)
            }
            "hunterShot" -> {
                if (s.hunterId == ctx.yourId) {
                    MonoLabel("Take one with you", color = Ub.Accent)
                    s.alive.filter { it.id != ctx.yourId }.chunked(2).forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            for (p in row) Box(Modifier.weight(1f)) { PickCell(s, p.id, p.name, false) }
                            if (row.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                    UbPrimaryButton("Fire", enabled = s.picked != null,
                        onClick = {
                            ctx.client.send(JSONObject().put("type", "hunter_shot").put("targetId", s.picked ?: ""))
                            s.picked = null
                        })
                } else {
                    InfoBanner("${s.playerName(s.hunterId ?: "")} is taking their last shot…")
                }
            }
            "gameOver" -> {
                val wolvesWin = s.winner == "werewolves"
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    MonoLabel("Game over", color = Ub.Accent)
                    Text(if (wolvesWin) "Werewolves win" else "Village wins", fontSize = 30.sp,
                         fontWeight = FontWeight.ExtraBold, letterSpacing = (-1).sp,
                         color = if (wolvesWin) Ub.Accent else Ub.Foreground)
                }
                MonoLabel("Full reveal")
                for ((_, name, role) in s.rolesReveal) {
                    val isWolf = role == "werewolf"
                    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Avatar(name, size = 30.dp)
                        Spacer(Modifier.width(12.dp))
                        Text(name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                        Spacer(Modifier.weight(1f))
                        Box(Modifier.clip(RoundedCornerShape(50))
                            .background(if (isWolf) Ub.Accent else Color.White.copy(alpha = 0.06f))
                            .padding(horizontal = 10.dp, vertical = 5.dp)) {
                            Text(role.replaceFirstChar { it.uppercase() }, fontSize = 12.sp,
                                 fontWeight = FontWeight.Bold, color = if (isWolf) Ub.OnAccent else Ub.Muted)
                        }
                    }
                }
            }
        }
        if (s.phase != "lobby" && (s.alive.size + s.dead.size) > 0) {
            MonoLabel("Players · ${s.alive.size} alive")
            val all = s.alive.map { it to true } + s.dead.map { it to false }
            all.chunked(2).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((p, isAlive) in row) Box(Modifier.weight(1f)) { PlayerCell(p.name, p.isHost, isAlive) }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
    }
    }
}

private fun phaseLabel(s: WerewolfGuestState): String = when (s.phase) {
    "night" -> "Werewolf · night ${maxOf(s.day, 1)}"
    "dayReveal" -> "Werewolf · dawn"
    "dayVote" -> "Werewolf · day ${s.day}"
    "hunterShot" -> "Werewolf · revenge"
    "gameOver" -> "Werewolf · over"
    else -> "Werewolf · lobby"
}

@Composable
private fun InfoBanner(text: String, accent: Boolean = false) {
    Box(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row,
            fill = if (accent) Ub.AccentSoft else Ub.Surface,
            stroke = if (accent) Ub.AccentLine else Ub.Line)
        .padding(horizontal = 16.dp, vertical = 14.dp)) {
        Text(text, fontSize = 14.sp, color = if (accent) Ub.Accent else Ub.Muted)
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
private fun PlayerCell(name: String, host: Boolean, alive: Boolean) {
    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.button,
            fill = if (alive) Ub.Surface else Ub.AccentSoft,
            stroke = if (alive) Ub.Line else Ub.AccentLine)
        .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Avatar(name, host = host, size = 28.dp)
        Spacer(Modifier.width(10.dp))
        Column {
            Text(name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                 color = if (alive) Ub.Foreground else Ub.Muted,
                 textDecoration = if (alive) null else TextDecoration.LineThrough)
            MonoLabel(if (alive) "alive" else "dead", size = 9,
                      color = if (alive) Ub.Faint else Ub.Accent)
        }
    }
}

@Composable
private fun PickCell(s: WerewolfGuestState, id: String, name: String, submitted: Boolean) {
    val selected = s.picked == id
    Row(Modifier.fillMaxWidth()
        .clip(RoundedCornerShape(10.dp))
        .background(if (selected) Ub.Accent else Color.White.copy(alpha = 0.05f))
        .then(if (selected) Modifier else Modifier.border(1.dp, Ub.LineStrong, RoundedCornerShape(10.dp)))
        .clickable(enabled = !submitted) { s.picked = id }
        .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (id != "__skip") { Avatar(name, size = 24.dp); Spacer(Modifier.width(8.dp)) }
        Text(name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
             color = if (selected) Ub.OnAccent else Color.White)
    }
}

@Composable
private fun RoleCard(s: WerewolfGuestState, myId: String) {
    val role = s.role ?: return
    val m = roleMeta(role)
    Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel,
            fill = if (m.accent) Ub.AccentSoft else Ub.Surface,
            stroke = if (m.accent) Ub.AccentLine else Ub.Line)
        .padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(48.dp).clip(RoundedCornerShape(12.dp))
                .background(if (m.accent) Ub.Accent else Ub.SurfaceHi),
                contentAlignment = Alignment.Center) {
                Text(m.letter, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold,
                     color = if (m.accent) Ub.OnAccent else Color.White)
            }
            Column {
                MonoLabel("Your role", size = 9, color = if (m.accent) Ub.Accent else Ub.Muted)
                Text(m.name, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Ub.Foreground)
            }
        }
        Text(m.blurb, fontSize = 13.sp, color = Ub.Muted)
        if (role == "werewolf" && s.wolfIds.size > 1) {
            val others = s.wolfIds.filter { it != myId }.map { s.playerName(it) }
            Column {
                MonoLabel("Your pack", size = 9)
                Text(others.joinToString(", "), fontSize = 13.sp,
                     fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
            }
        }
    }
}

private fun roleMeta(role: String): RoleMeta = when (role) {
    "werewolf" -> RoleMeta("Werewolf", "Hunt the village by night. You can see your pack.", "W", true)
    "seer" -> RoleMeta("Seer", "Each night, learn whether one player is a werewolf.", "?", false)
    "hunter" -> RoleMeta("Hunter", "When you die you take one player down with you.", "H", false)
    "villager" -> RoleMeta("Villager", "No night power — survive and vote wisely.", "V", false)
    else -> RoleMeta(role.replaceFirstChar { it.uppercase() }, role, "•", false)
}

private data class RoleMeta(val name: String, val blurb: String, val letter: String, val accent: Boolean)

@Composable
private fun SeerFindings(s: WerewolfGuestState) {
    if (s.role != "seer" || s.seerHistory.isEmpty()) return
    MonoLabel("Seer findings")
    for (r in s.seerHistory) {
        Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row)
            .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text("Night ${r.day} · ${s.playerName(r.targetId)}", fontSize = 13.sp, color = Ub.Foreground)
            Spacer(Modifier.weight(1f))
            Text(if (r.isWerewolf) "WEREWOLF" else "not a wolf", fontSize = 11.sp,
                 fontWeight = FontWeight.Bold, color = if (r.isWerewolf) Ub.Accent else Ub.Online)
        }
    }
}

@Composable
private fun LastNight(s: WerewolfGuestState) {
    val k = s.lastNightKilled
    val txt = when {
        k != null -> "${s.playerName(k)} was killed in the night."
        s.nightResolved -> "A quiet night. No one died."
        else -> null
    }
    if (txt != null) InfoBanner(txt)
}

@Composable
private fun TargetPicker(s: WerewolfGuestState, prompt: String,
                         targets: List<WerewolfGuestState.Player>, kind: String,
                         verb: String, allowSkip: Boolean, ctx: GuestContext) {
    val submitted = s.submittedKind == kind && s.submittedDay == s.day
    MonoLabel(prompt)
    val cells = targets.map { it.id to it.name } + if (allowSkip) listOf("__skip" to "Skip vote") else emptyList()
    cells.chunked(2).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((id, name) in row) Box(Modifier.weight(1f)) { PickCell(s, id, name, submitted) }
            if (row.size == 1) Spacer(Modifier.weight(1f))
        }
    }
    Spacer(Modifier.height(2.dp))
    UbPrimaryButton(if (submitted) "Submitted" else verb,
        enabled = !submitted && s.picked != null,
        onClick = {
            val payload = JSONObject().put("type", if (kind == "night") "night_action" else "vote")
            if (kind == "vote" && s.picked == "__skip") payload.put("targetId", JSONObject.NULL)
            else payload.put("targetId", s.picked ?: "")
            ctx.client.send(payload)
            s.submittedKind = kind; s.submittedDay = s.day
        })
}

class WerewolfGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean, val alive: Boolean)
    data class Seer(val targetId: String, val isWerewolf: Boolean, val day: Int)

    var lobby by mutableStateOf<List<Player>>(emptyList())
    var alive by mutableStateOf<List<Player>>(emptyList())
    var dead by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var day by mutableIntStateOf(0)
    var role by mutableStateOf<String?>(null)
    var wolfIds by mutableStateOf<List<String>>(emptyList())
    var lastNightKilled by mutableStateOf<String?>(null)
    var nightResolved by mutableStateOf(false)
    var seerHistory by mutableStateOf<List<Seer>>(emptyList())
    var hunterId by mutableStateOf<String?>(null)
    var winner by mutableStateOf<String?>(null)
    var rolesReveal by mutableStateOf<List<Triple<String, String, String>>>(emptyList())
    var error by mutableStateOf<String?>(null)
    var picked by mutableStateOf<String?>(null)
    var submittedKind by mutableStateOf<String?>(null)
    var submittedDay by mutableStateOf<Int?>(null)
    var tutorialState by mutableStateOf(GuestTutorialState())
    var tutorialContent by mutableStateOf<GuestTutorialContent?>(null)
    var myTutorialVote by mutableStateOf<Boolean?>(null)

    fun playerName(id: String) = (alive + dead + lobby).firstOrNull { it.id == id }?.name ?: id

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
            "lobby" -> {
                val arr = m.optJSONArray("players") ?: return
                lobby = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"), o.optBoolean("isHost"), true)
                }
            }
            "role" -> {
                role = m.optString("role")
                val a = m.optJSONArray("wolfIds")
                wolfIds = if (a == null) emptyList() else (0 until a.length()).map { a.getString(it) }
            }
            "phase" -> {
                val prev = phase
                phase = m.optString("phase")
                day = m.optInt("day", day)
                alive = readPlayers(m.optJSONArray("alive"))
                dead = readPlayers(m.optJSONArray("dead"))
                if (m.has("killedId")) {
                    lastNightKilled = if (m.isNull("killedId")) null else m.optString("killedId").ifEmpty { null }
                    nightResolved = true
                }
                if (prev != phase) picked = null
            }
            "seer_result" -> {
                seerHistory = seerHistory + Seer(m.optString("targetId"),
                                                  m.optBoolean("isWerewolf"), day)
            }
            "hunter_prompt" -> {
                phase = "hunterShot"
                hunterId = m.optString("hunterId")
                alive = readPlayers(m.optJSONArray("alive"))
                dead = readPlayers(m.optJSONArray("dead"))
                picked = null
            }
            "hunter_shot_result", "day_result" -> {
                alive = readPlayers(m.optJSONArray("alive"))
                dead = readPlayers(m.optJSONArray("dead"))
            }
            "game_over" -> {
                phase = "gameOver"
                winner = m.optString("winner")
                val roles = m.optJSONObject("roles")
                if (roles != null) {
                    val combined = (lobby + alive + dead).associateBy { it.id }
                    rolesReveal = roles.keys().asSequence().map {
                        Triple(it, combined[it]?.name ?: it, roles.optString(it))
                    }.sortedBy { it.second }.toList()
                }
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
            "error" -> error = m.optString("message")
        }
    }

    private fun readPlayers(arr: org.json.JSONArray?): List<Player> {
        if (arr == null) return emptyList()
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            Player(o.optString("id"), o.optString("name"), false, o.optBoolean("alive", true))
        }
    }
}
