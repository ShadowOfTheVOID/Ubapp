package com.example.ubapp.games.werewolf

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
fun WerewolfGuestScreen(ctx: GuestContext) {
    val s = remember { WerewolfGuestState() }
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
                Text("Players (${s.lobby.size})", style = MaterialTheme.typography.titleSmall)
                for (p in s.lobby) Text(p.name + if (p.isHost) " (host)" else "")
            }
            "night" -> {
                RoleCard(s, ctx.yourId)
                val alive = s.alive.any { it.id == ctx.yourId }
                if (!alive) Text("Watching from the sidelines.")
                else when (s.role) {
                    "werewolf" -> TargetPicker(s, "Choose a victim",
                        s.alive.filter { it.id != ctx.yourId && it.id !in s.wolfIds }, "night", false, ctx)
                    "seer" -> TargetPicker(s, "Investigate a player",
                        s.alive.filter { it.id != ctx.yourId }, "night", false, ctx)
                    else -> Text("Wolves and seer are acting…")
                }
                SeerFindings(s)
            }
            "dayReveal" -> { RoleCard(s, ctx.yourId); LastNight(s); SeerFindings(s) }
            "dayVote" -> {
                RoleCard(s, ctx.yourId); LastNight(s); SeerFindings(s)
                val alive = s.alive.any { it.id == ctx.yourId }
                if (!alive) Text("Watching from the sidelines.")
                else TargetPicker(s, "Vote to lynch",
                                  s.alive.filter { it.id != ctx.yourId }, "vote", true, ctx)
            }
            "hunterShot" -> {
                if (s.hunterId == ctx.yourId) {
                    Text("Take one with you", style = MaterialTheme.typography.titleSmall)
                    for (p in s.alive.filter { it.id != ctx.yourId }) {
                        OutlinedButton(onClick = { s.picked = p.id },
                                       modifier = Modifier.fillMaxWidth()) {
                            Row(Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween)
                            { Text(p.name); if (s.picked == p.id) Text("✓") }
                        }
                    }
                    Button(onClick = {
                        ctx.client.send(JSONObject().put("type", "hunter_shot")
                                                    .put("targetId", s.picked ?: ""))
                        s.picked = null
                    }, enabled = s.picked != null,
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828)))
                    { Text("Fire") }
                } else {
                    Text("${s.playerName(s.hunterId ?: "")} is taking their last shot…")
                }
            }
            "gameOver" -> {
                Text(if (s.winner == "werewolves") "Werewolves win" else "Village wins",
                     style = MaterialTheme.typography.headlineSmall)
                for ((id, name, role) in s.rolesReveal) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween)
                    { Text(name); Text(role.replaceFirstChar { it.uppercase() }) }
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
private fun RoleCard(s: WerewolfGuestState, myId: String) {
    val role = s.role ?: return
    val (label, blurb) = when (role) {
        "werewolf" -> "Your role: Werewolf" to "Hunt the village. You can see your pack."
        "seer" -> "Your role: Seer" to "Each night, learn if one player is a werewolf."
        "hunter" -> "Your role: Hunter" to "When you die you take one player down with you."
        else -> "Your role: Villager" to "Survive and vote wisely."
    }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text(label, style = MaterialTheme.typography.titleSmall)
            Text(blurb, style = MaterialTheme.typography.bodyMedium)
            if (role == "werewolf" && s.wolfIds.size > 1) {
                val others = s.wolfIds.filter { it != myId }.map { s.playerName(it) }
                Text("Your pack: ${others.joinToString(", ")}",
                     style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun SeerFindings(s: WerewolfGuestState) {
    if (s.role != "seer" || s.seerHistory.isEmpty()) return
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text("Seer findings", style = MaterialTheme.typography.titleSmall)
            for (r in s.seerHistory) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Night ${r.day}: ${s.playerName(r.targetId)}")
                    Text(if (r.isWerewolf) "IS a werewolf" else "is not a werewolf",
                         color = if (r.isWerewolf) Color(0xFFC62828) else Color(0xFF2E7D32))
                }
            }
        }
    }
}

@Composable
private fun LastNight(s: WerewolfGuestState) {
    val k = s.lastNightKilled
    val txt = when {
        k != null -> "${s.playerName(k)} was killed in the night."
        s.nightResolved -> "A quiet night."
        else -> null
    }
    if (txt != null) Text(txt)
}

@Composable
private fun TargetPicker(s: WerewolfGuestState, prompt: String,
                         targets: List<WerewolfGuestState.Player>, kind: String,
                         allowSkip: Boolean, ctx: GuestContext) {
    val submitted = s.submittedKind == kind && s.submittedDay == s.day
    Text(prompt, style = MaterialTheme.typography.titleSmall)
    for (p in targets) OutlinedButton(
        onClick = { s.picked = p.id }, modifier = Modifier.fillMaxWidth(),
        enabled = !submitted,
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween)
        { Text(p.name); if (s.picked == p.id) Text("✓") }
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
