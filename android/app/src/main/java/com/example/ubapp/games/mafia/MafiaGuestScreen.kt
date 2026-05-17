package com.example.ubapp.games.mafia

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
import org.json.JSONObject

@Composable
fun MafiaGuestScreen(ctx: GuestContext) {
    val s = remember { MafiaGuestState() }
    var tick by remember { mutableIntStateOf(0) }
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
        if (s.error != null) Text(s.error!!, color = MaterialTheme.colorScheme.error)
        when (s.phase) {
            "lobby" -> {
                TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                    onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                    onVote = { yes -> s.myTutorialVote = yes
                        ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                Text("Lobby (${s.lobby.size})", style = MaterialTheme.typography.titleSmall)
                for (p in s.lobby) {
                    Text(p.name + (if (p.isHost) " (host)" else "") +
                         (if (p.id == ctx.yourId) " — you" else ""))
                }
                Text("Waiting for the host to start…", style = MaterialTheme.typography.bodySmall)
            }
            "night" -> {
                RoleCard(s.role, s.mafiaIds, ctx.yourId, s)
                val iAmAlive = s.alive.any { it.id == ctx.yourId }
                if (!iAmAlive) Text("Watching from the sidelines.")
                else when (s.role) {
                    "mafia" -> TargetPicker(s, "Choose someone to eliminate",
                        s.alive.filter { it.id != ctx.yourId }, "night", false, ctx)
                    "doctor" -> TargetPicker(s, "Choose someone to save",
                        s.alive, "night", false, ctx)
                    else -> Text("Mafia and doctor are acting…",
                                  style = MaterialTheme.typography.bodyMedium)
                }
            }
            "dayReveal" -> {
                LastNight(s)
            }
            "dayVote" -> {
                LastNight(s)
                val iAmAlive = s.alive.any { it.id == ctx.yourId }
                if (!iAmAlive) Text("Watching from the sidelines.")
                else TargetPicker(s, "Vote to eliminate",
                                  s.alive.filter { it.id != ctx.yourId }, "vote", true, ctx)
            }
            "gameOver" -> {
                Text(if (s.winner == "mafia") "Mafia win" else "Town wins",
                     style = MaterialTheme.typography.headlineSmall)
                for ((id, name, role) in s.rolesReveal) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(name); Text(role.replaceFirstChar { it.uppercase() })
                    }
                }
            }
        }
        if (s.phase != "lobby" && (s.alive.size + s.dead.size) > 0) {
            Spacer(Modifier.height(8.dp))
            Text("Players", style = MaterialTheme.typography.titleSmall)
            for (p in s.alive) Row(Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween)
            { Text(p.name); Text("alive", color = Color(0xFF2E7D32)) }
            for (p in s.dead) Row(Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween)
            { Text(p.name); Text("dead", color = Color(0xFFC62828)) }
        }
    }
}

@Composable
private fun RoleCard(role: String?, mafiaIds: List<String>, myId: String, s: MafiaGuestState) {
    if (role == null) return
    val (label, blurb) = when (role) {
        "mafia" -> "Your role: Mafia" to "Eliminate the town. You can see your fellow mafia."
        "doctor" -> "Your role: Doctor" to "Save one player each night. Self-save once per game."
        else -> "Your role: Villager" to "Use your vote during the day."
    }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text(label, style = MaterialTheme.typography.titleSmall)
            Text(blurb, style = MaterialTheme.typography.bodyMedium)
            if (role == "mafia" && mafiaIds.size > 1) {
                val others = mafiaIds.filter { it != myId }
                    .mapNotNull { id -> (s.lobby + s.alive + s.dead).firstOrNull { it.id == id }?.name }
                if (others.isNotEmpty())
                    Text("Your fellow mafia: ${others.joinToString(", ")}",
                         style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun LastNight(s: MafiaGuestState) {
    val k = s.lastNightKilled
    val text = when {
        k != null -> "${s.playerName(k)} was killed in the night."
        s.lastNightSaved != null -> "The doctor saved someone — no one died."
        s.nightResolved -> "A quiet night."
        else -> null
    }
    if (text != null) Text(text, style = MaterialTheme.typography.bodyMedium)
}

@Composable
private fun TargetPicker(s: MafiaGuestState, prompt: String,
                         targets: List<MafiaGuestState.Player>, kind: String,
                         allowSkip: Boolean, ctx: GuestContext) {
    val submitted = s.submittedKind == kind && s.submittedDay == s.day
    Text(prompt, style = MaterialTheme.typography.titleSmall)
    for (p in targets) {
        OutlinedButton(
            onClick = { s.picked = p.id },
            modifier = Modifier.fillMaxWidth(),
            enabled = !submitted,
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(p.name); if (s.picked == p.id) Text("✓")
            }
        }
    }
    if (allowSkip) OutlinedButton(
        onClick = { s.picked = "__skip" }, modifier = Modifier.fillMaxWidth(),
        enabled = !submitted,
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween)
        { Text("Skip vote"); if (s.picked == "__skip") Text("✓") }
    }
    Button(
        onClick = {
            val payload = JSONObject().put("type", if (kind == "night") "night_action" else "vote")
            if (kind == "vote" && s.picked == "__skip") payload.put("targetId", JSONObject.NULL)
            else payload.put("targetId", s.picked ?: "")
            ctx.client.send(payload)
            s.submittedKind = kind; s.submittedDay = s.day
        },
        enabled = !submitted && s.picked != null,
    ) { Text(if (submitted) "Submitted" else "Confirm") }
}

class MafiaGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean, val alive: Boolean)
    var lobby by mutableStateOf<List<Player>>(emptyList())
    var alive by mutableStateOf<List<Player>>(emptyList())
    var dead by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var day by mutableIntStateOf(0)
    var role by mutableStateOf<String?>(null)
    var mafiaIds by mutableStateOf<List<String>>(emptyList())
    var lastNightKilled by mutableStateOf<String?>(null)
    var lastNightSaved by mutableStateOf<String?>(null)
    var nightResolved by mutableStateOf(false)
    var winner by mutableStateOf<String?>(null)
    var rolesReveal by mutableStateOf<List<Triple<String, String, String>>>(emptyList())
    var error by mutableStateOf<String?>(null)
    var picked by mutableStateOf<String?>(null)
    var submittedKind by mutableStateOf<String?>(null)
    var submittedDay by mutableStateOf<Int?>(null)
    var tutorialState by mutableStateOf(GuestTutorialState())
    var tutorialContent by mutableStateOf<GuestTutorialContent?>(null)
    var myTutorialVote by mutableStateOf<Boolean?>(null)

    fun playerName(id: String): String =
        (alive + dead + lobby).firstOrNull { it.id == id }?.name ?: id

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
            "lobby" -> {
                val arr = m.optJSONArray("players")
                lobby = if (arr == null) emptyList() else (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"), o.optBoolean("isHost"), true)
                }
            }
            "role" -> {
                role = m.optString("role")
                val a = m.optJSONArray("mafiaIds")
                mafiaIds = if (a == null) emptyList() else (0 until a.length()).map { a.getString(it) }
            }
            "phase" -> {
                val prev = phase
                phase = m.optString("phase")
                day = m.optInt("day", day)
                alive = readPlayers(m.optJSONArray("alive"))
                dead = readPlayers(m.optJSONArray("dead"))
                if (m.has("killedId") || m.has("savedId")) {
                    lastNightKilled = if (m.isNull("killedId")) null else m.optString("killedId").ifEmpty { null }
                    lastNightSaved = if (m.isNull("savedId")) null else m.optString("savedId").ifEmpty { null }
                    nightResolved = true
                }
                if (prev != phase) picked = null
            }
            "day_result" -> {
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
