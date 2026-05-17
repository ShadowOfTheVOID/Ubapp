package com.example.ubapp.games.secrethitler

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.ubapp.join.GuestContext
import com.example.ubapp.join.GuestTutorialContent
import com.example.ubapp.join.GuestTutorialState
import com.example.ubapp.join.TutorialGuestCard
import org.json.JSONObject

@Composable
fun SecretHitlerGuestScreen(ctx: GuestContext) {
    val s = remember { SecretHitlerGuestState() }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(ctx) {
        ctx.client.onMessage = { msg -> s.handle(msg); tick++ }
        for (m in ctx.replay) s.handle(m)
        onDispose { ctx.client.onMessage = null }
    }
    @Suppress("UNUSED_EXPRESSION") tick

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
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
                Text("5–10 players. Waiting for the host to start…",
                     style = MaterialTheme.typography.bodySmall)
            }
            "gameOver" -> {
                val winText = if (s.winner == "liberal") "Liberals win" else "Fascists win"
                Text(winText, style = MaterialTheme.typography.headlineSmall)
                Text(when (s.reason) {
                    "fiveLiberalPolicies" -> "Five Liberal policies enacted."
                    "sixFascistPolicies" -> "Six Fascist policies enacted."
                    "hitlerElectedChancellor" -> "Hitler was elected Chancellor."
                    "hitlerExecuted" -> "Hitler was executed."
                    else -> ""
                })
                for (p in s.players) Row(Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween)
                { Text(p.name); Text((s.finalRoles[p.id] ?: "—").replaceFirstChar { it.uppercase() }) }
            }
            else -> {
                RoleCard(s)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TrackCell("Liberal", "${s.liberalPolicies} / 5", Color(0xFF2D6CDF))
                    TrackCell("Fascist", "${s.fascistPolicies} / 6", Color(0xFFC2410C))
                    TrackCell("Election", "${s.electionTracker} / 3", MaterialTheme.colorScheme.onSurface)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column { Text("President", style = MaterialTheme.typography.labelSmall)
                        Text(s.playerName(s.presidentId), fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) }
                    Column(horizontalAlignment = Alignment.End) {
                        Text("Chancellor", style = MaterialTheme.typography.labelSmall)
                        Text(s.playerName(s.chancellorId ?: s.chancellorNomineeId),
                             fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) }
                }
                PhaseSection(s, ctx)
            }
        }
    }
}

@Composable
private fun RowScope.TrackCell(label: String, value: String, color: Color) {
    ElevatedCard(Modifier.weight(1f)) {
        Column(Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelSmall)
            Text(value, style = MaterialTheme.typography.titleMedium, color = color)
        }
    }
}

@Composable
private fun RoleCard(s: SecretHitlerGuestState) {
    val role = s.role ?: return
    val (label, blurb) = when (role) {
        "liberal" -> "Your role: Liberal" to "Pass 5 Liberal policies or have Hitler executed."
        "fascist" -> "Your role: Fascist" to "Pass 6 Fascist policies or sneak Hitler in as Chancellor."
        "hitler" -> "Your role: Hitler" to "Stay hidden. Get elected Chancellor after 3 Fascist policies."
        else -> "Your role" to role
    }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text(label, style = MaterialTheme.typography.titleSmall)
            Text(blurb, style = MaterialTheme.typography.bodyMedium)
            if (s.allies.isNotEmpty()) {
                Text("Allies: " + s.allies.joinToString(", ") {
                    if (it.role == "hitler") "${it.name} (Hitler)" else it.name
                }, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun PhaseSection(s: SecretHitlerGuestState, ctx: GuestContext) {
    val amPresident = s.presidentId == ctx.yourId
    val amChancellor = s.chancellorId == ctx.yourId
    val meAlive = s.players.firstOrNull { it.id == ctx.yourId }?.alive == true

    when (s.phase) {
        "nomination" -> {
            if (amPresident) {
                Text("Nominate a Chancellor", style = MaterialTheme.typography.titleSmall)
                val eligible = s.players.filter { it.id in s.eligibleChancellors }
                for (p in eligible) OutlinedButton(
                    onClick = { ctx.client.send(JSONObject().put("type", "nominate")
                                                            .put("targetId", p.id)) },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(p.name) }
            } else Waiting("${s.playerName(s.presidentId)} is nominating a Chancellor")
        }
        "election" -> {
            if (!meAlive) Waiting("Watching from the sidelines")
            else if (s.voted) Text("Vote locked in. ${s.voteProgress} / ${s.voteTotal} have voted.")
            else {
                Text("Vote on the government", style = MaterialTheme.typography.titleSmall)
                Text("${s.playerName(s.presidentId)} / ${s.playerName(s.chancellorNomineeId)}",
                     style = MaterialTheme.typography.bodySmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        ctx.client.send(JSONObject().put("type", "vote").put("ja", true))
                        s.voted = true
                    }, modifier = Modifier.weight(1f),
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)))
                    { Text("Ja!") }
                    Button(onClick = {
                        ctx.client.send(JSONObject().put("type", "vote").put("ja", false))
                        s.voted = true
                    }, modifier = Modifier.weight(1f),
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828)))
                    { Text("Nein!") }
                }
                Text("${s.voteProgress} / ${s.voteTotal} voted",
                     style = MaterialTheme.typography.bodySmall)
            }
        }
        "presidentDiscard" -> {
            if (amPresident && s.presidentialHand != null) {
                Text("Discard one — two go to the Chancellor",
                     style = MaterialTheme.typography.titleSmall)
                s.presidentialHand!!.forEachIndexed { i, pol ->
                    OutlinedButton(onClick = {
                        ctx.client.send(JSONObject().put("type", "discard").put("index", i))
                    }, modifier = Modifier.fillMaxWidth()) {
                        Text("Discard ${policyLabel(pol)}")
                    }
                }
            } else Waiting("${s.playerName(s.presidentId)} is discarding")
        }
        "chancellorEnact" -> {
            if (amChancellor && s.chancellorHand != null) {
                Text("Enact one policy", style = MaterialTheme.typography.titleSmall)
                s.chancellorHand!!.forEachIndexed { i, pol ->
                    OutlinedButton(onClick = {
                        ctx.client.send(JSONObject().put("type", "enact").put("index", i))
                    }, modifier = Modifier.fillMaxWidth()) {
                        Text("Enact ${policyLabel(pol)}")
                    }
                }
                if (s.vetoUnlocked) TextButton(onClick = {
                    ctx.client.send(JSONObject().put("type", "request_veto"))
                }) { Text("Request veto") }
            } else Waiting("${s.playerName(s.chancellorId)} is enacting")
        }
        "vetoDecision" -> {
            if (amPresident) {
                Text("Chancellor wants to veto", style = MaterialTheme.typography.titleSmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        ctx.client.send(JSONObject().put("type", "veto_response").put("confirm", true))
                    }, modifier = Modifier.weight(1f),
                       colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEF6C00)))
                    { Text("Agree — veto") }
                    OutlinedButton(onClick = {
                        ctx.client.send(JSONObject().put("type", "veto_response").put("confirm", false))
                    }, modifier = Modifier.weight(1f)) { Text("Refuse") }
                }
            } else Waiting("Veto requested — ${s.playerName(s.presidentId)} is deciding")
        }
        "policyPeek" -> {
            if (amPresident && s.peekedPolicies != null) {
                Text("Top three policies", style = MaterialTheme.typography.titleSmall)
                s.peekedPolicies!!.forEachIndexed { i, p ->
                    Text("${i+1}. ${policyLabel(p)}")
                }
                Button(onClick = { ctx.client.send(JSONObject().put("type", "ack_peek")) })
                { Text("Done") }
            } else Waiting("${s.playerName(s.presidentId)} is peeking at the deck")
        }
        "investigation" -> {
            if (amPresident) {
                Text("Investigate a player's party", style = MaterialTheme.typography.titleSmall)
                val targets = s.players.filter {
                    it.alive && it.id != s.presidentId && it.id !in s.investigatedIds
                }
                for (p in targets) OutlinedButton(onClick = {
                    ctx.client.send(JSONObject().put("type", "investigate").put("targetId", p.id))
                }, modifier = Modifier.fillMaxWidth()) { Text(p.name) }
            } else Waiting("${s.playerName(s.presidentId)} is investigating")
        }
        "investigationReveal" -> {
            if (amPresident && s.investigationResult != null) {
                val inv = s.investigationResult!!
                Text("${s.playerName(inv.subjectId)} is ${inv.party.replaceFirstChar { it.uppercase() }}",
                     style = MaterialTheme.typography.titleSmall)
                Text("Share it or lie about it.", style = MaterialTheme.typography.bodySmall)
                Button(onClick = { ctx.client.send(JSONObject().put("type", "ack_investigation")) })
                { Text("Done") }
            } else Waiting("${s.playerName(s.presidentId)} has the investigation result")
        }
        "specialElection" -> {
            if (amPresident) {
                Text("Pick the next President", style = MaterialTheme.typography.titleSmall)
                for (p in s.players.filter { it.alive && it.id != s.presidentId }) {
                    OutlinedButton(onClick = {
                        ctx.client.send(JSONObject().put("type", "special_election").put("targetId", p.id))
                    }, modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
            } else Waiting("${s.playerName(s.presidentId)} is calling a special election")
        }
        "execution" -> {
            if (amPresident) {
                Text("Execute a player", style = MaterialTheme.typography.titleSmall)
                for (p in s.players.filter { it.alive && it.id != s.presidentId }) {
                    OutlinedButton(onClick = {
                        ctx.client.send(JSONObject().put("type", "execute").put("targetId", p.id))
                    }, modifier = Modifier.fillMaxWidth()) { Text(p.name) }
                }
            } else Waiting("${s.playerName(s.presidentId)} is choosing someone to execute")
        }
    }
}

@Composable
private fun Waiting(msg: String) {
    Text("$msg…", style = MaterialTheme.typography.bodyMedium,
         color = MaterialTheme.colorScheme.onSurfaceVariant)
}

private fun policyLabel(p: String): String = if (p == "liberal") "Liberal policy" else "Fascist policy"

class SecretHitlerGuestState {
    data class Player(val id: String, val name: String, val isHost: Boolean, val alive: Boolean)
    data class Ally(val id: String, val name: String, val role: String)
    data class Investigation(val subjectId: String, val party: String)

    var players by mutableStateOf<List<Player>>(emptyList())
    var phase by mutableStateOf("lobby")
    var presidentId by mutableStateOf<String?>(null)
    var chancellorNomineeId by mutableStateOf<String?>(null)
    var chancellorId by mutableStateOf<String?>(null)
    var liberalPolicies by mutableIntStateOf(0)
    var fascistPolicies by mutableIntStateOf(0)
    var electionTracker by mutableIntStateOf(0)
    var vetoUnlocked by mutableStateOf(false)
    var vetoRequested by mutableStateOf(false)
    var eligibleChancellors by mutableStateOf<List<String>>(emptyList())
    var voteProgress by mutableIntStateOf(0)
    var voteTotal by mutableIntStateOf(0)
    var voted by mutableStateOf(false)
    var investigatedIds by mutableStateOf<List<String>>(emptyList())
    var role by mutableStateOf<String?>(null)
    var allies by mutableStateOf<List<Ally>>(emptyList())
    var presidentialHand by mutableStateOf<List<String>?>(null)
    var chancellorHand by mutableStateOf<List<String>?>(null)
    var peekedPolicies by mutableStateOf<List<String>?>(null)
    var investigationResult by mutableStateOf<Investigation?>(null)
    var winner by mutableStateOf<String?>(null)
    var reason by mutableStateOf<String?>(null)
    var finalRoles by mutableStateOf<Map<String, String>>(emptyMap())
    var tutorialState by mutableStateOf(GuestTutorialState())
    var tutorialContent by mutableStateOf<GuestTutorialContent?>(null)
    var myTutorialVote by mutableStateOf<Boolean?>(null)

    fun playerName(id: String?): String =
        id?.let { players.firstOrNull { p -> p.id == it }?.name } ?: "—"

    fun handle(m: JSONObject) {
        when (m.optString("type")) {
            "role" -> {
                role = m.optString("role")
                val a = m.optJSONArray("allies")
                allies = if (a == null) emptyList() else (0 until a.length()).map {
                    val o = a.getJSONObject(it)
                    Ally(o.optString("id"), o.optString("name"), o.optString("role"))
                }
            }
            "state" -> {
                val prev = phase
                phase = m.optString("phase", phase)
                val arr = m.optJSONArray("players")
                if (arr != null) players = (0 until arr.length()).map {
                    val o = arr.getJSONObject(it)
                    Player(o.optString("id"), o.optString("name"),
                           o.optBoolean("isHost"), o.optBoolean("alive", true))
                }
                presidentId = m.optString("presidentId").ifEmpty { null }.takeIf { !m.isNull("presidentId") }
                chancellorNomineeId = m.optString("chancellorNomineeId").ifEmpty { null }.takeIf { !m.isNull("chancellorNomineeId") }
                chancellorId = m.optString("chancellorId").ifEmpty { null }.takeIf { !m.isNull("chancellorId") }
                liberalPolicies = m.optInt("liberalPolicies", liberalPolicies)
                fascistPolicies = m.optInt("fascistPolicies", fascistPolicies)
                electionTracker = m.optInt("electionTracker", electionTracker)
                vetoUnlocked = m.optBoolean("vetoUnlocked", vetoUnlocked)
                vetoRequested = m.optBoolean("vetoRequested", false)
                val ec = m.optJSONArray("eligibleChancellors")
                eligibleChancellors = if (ec == null) emptyList()
                    else (0 until ec.length()).map { ec.getString(it) }
                voteProgress = m.optInt("voteProgress", 0)
                voteTotal = m.optInt("voteTotal", 0)
                val ii = m.optJSONArray("investigatedIds")
                investigatedIds = if (ii == null) emptyList()
                    else (0 until ii.length()).map { ii.getString(it) }
                if (prev != phase) {
                    voted = false
                    if (phase != "presidentDiscard") presidentialHand = null
                    if (phase != "chancellorEnact" && phase != "vetoDecision") chancellorHand = null
                    if (phase != "policyPeek") peekedPolicies = null
                    if (phase != "investigationReveal") investigationResult = null
                }
            }
            "vote_progress" -> {
                voteProgress = m.optInt("voteProgress", voteProgress)
                voteTotal = m.optInt("voteTotal", voteTotal)
            }
            "election_result" -> electionTracker = m.optInt("electionTracker", electionTracker)
            "policy_enacted" -> {
                liberalPolicies = m.optInt("liberalPolicies", liberalPolicies)
                fascistPolicies = m.optInt("fascistPolicies", fascistPolicies)
            }
            "veto_confirmed" -> electionTracker = m.optInt("electionTracker", electionTracker)
            "presidential_hand" -> {
                val arr = m.optJSONArray("policies")
                presidentialHand = if (arr == null) null else (0 until arr.length()).map { arr.getString(it) }
            }
            "chancellor_hand" -> {
                val arr = m.optJSONArray("policies")
                chancellorHand = if (arr == null) null else (0 until arr.length()).map { arr.getString(it) }
                vetoUnlocked = m.optBoolean("vetoUnlocked", vetoUnlocked)
            }
            "policy_peek" -> {
                val arr = m.optJSONArray("policies")
                peekedPolicies = if (arr == null) null else (0 until arr.length()).map { arr.getString(it) }
            }
            "investigation_result" -> {
                investigationResult = Investigation(m.optString("subjectId"), m.optString("party"))
            }
            "game_over" -> {
                phase = "gameOver"
                winner = m.optString("winner").ifEmpty { null }
                reason = m.optString("reason").ifEmpty { null }
                val roles = m.optJSONObject("roles")
                if (roles != null) finalRoles = roles.keys().asSequence()
                    .associateWith { roles.optString(it) }
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
