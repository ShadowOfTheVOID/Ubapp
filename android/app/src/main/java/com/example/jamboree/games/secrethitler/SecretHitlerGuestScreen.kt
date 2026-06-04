package com.example.jamboree.games.secrethitler

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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.ads.AdBanner
import com.example.jamboree.ads.AdBannerPlacement
import com.example.jamboree.ads.AdInterstitialController
import com.example.jamboree.theme.Avatar
import com.example.jamboree.theme.LobbyPlayerRow
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.UbSecondaryButton
import com.example.jamboree.theme.JamboreeTheme
import com.example.jamboree.theme.ubCard
import com.example.jamboree.join.GuestContext
import com.example.jamboree.join.GuestTutorialContent
import com.example.jamboree.join.GuestTutorialState
import com.example.jamboree.join.TutorialGuestCard
import com.example.jamboree.shared.TeamChat
import com.example.jamboree.shared.TeamChatMessage
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
    Box(Modifier.weight(1f), contentAlignment = Alignment.TopCenter) {
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
        when (s.phase) {
            "lobby" -> {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    MonoLabel("Secret Hitler · lobby", color = Ub.Accent)
                    Text("Waiting for the deal", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold,
                         letterSpacing = (-0.8).sp, color = Ub.Foreground)
                    Text("Playing as ${ctx.yourName} · 5–10 players", fontSize = 13.sp, color = Ub.Muted)
                }
                TutorialGuestCard(s.tutorialState, s.tutorialContent, s.myTutorialVote,
                    onCall = { ctx.client.send(JSONObject().put("type", "call_tutorial_vote")) },
                    onVote = { yes -> s.myTutorialVote = yes
                        ctx.client.send(JSONObject().put("type", "tutorial_vote").put("yes", yes)) })
                MonoLabel("In the room · ${s.players.size}")
                for (p in s.players) LobbyPlayerRow(p.name, p.isHost)
            }
            "gameOver" -> {
                val liberalWin = s.winner == "liberal"
                val color = if (liberalWin) Sh.Liberal else Sh.Fascist
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    MonoLabel("Game over", color = color)
                    Text(if (liberalWin) "Liberals win" else "Fascists win", fontSize = 30.sp,
                         fontWeight = FontWeight.ExtraBold, letterSpacing = (-1).sp, color = color)
                    val reason = when (s.reason) {
                        "fiveLiberalPolicies" -> "Five Liberal policies enacted."
                        "sixFascistPolicies" -> "Six Fascist policies enacted."
                        "hitlerElectedChancellor" -> "Hitler was elected Chancellor."
                        "hitlerExecuted" -> "Hitler was executed."
                        else -> ""
                    }
                    if (reason.isNotEmpty()) Text(reason, fontSize = 13.sp, color = Ub.Muted)
                }
                Tracks(s)
                MonoLabel("Full reveal")
                for (p in s.players) {
                    val role = s.finalRoles[p.id] ?: ""
                    val fascistSide = role == "fascist" || role == "hitler"
                    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row,
                            fill = if (fascistSide) Sh.Fascist.copy(alpha = 0.10f) else Ub.Surface,
                            stroke = if (fascistSide) Sh.Fascist.copy(alpha = 0.45f) else Ub.Line)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Avatar(p.name, host = p.isHost, size = 30.dp)
                        Spacer(Modifier.width(12.dp))
                        Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                        Spacer(Modifier.weight(1f))
                        Text(role.replaceFirstChar { it.uppercase() }, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                             color = if (role == "hitler") Color.White else if (fascistSide) Sh.Fascist else Sh.Liberal)
                    }
                }
            }
            else -> {
                RoleCard(s)
                Tracks(s)
                Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    SlatePerson(s.playerName(s.presidentId), "President")
                    Text("×", fontSize = 22.sp, color = Ub.Muted)
                    SlatePerson(s.playerName(s.chancellorId ?: s.chancellorNomineeId), "Chancellor")
                }
                PhaseSection(s, ctx)
                if (s.role != null && s.allies.isNotEmpty()) {
                    val alive = s.players.firstOrNull { it.id == ctx.yourId }?.alive == true
                    TeamChat(
                        title = "Fascist chat",
                        subtitle = if (alive) "Private — only fascists you know can read this."
                                   else "You're out — chat is read-only.",
                        messages = s.chat,
                        myId = ctx.yourId,
                        enabled = alive,
                        onSend = { text -> ctx.client.send(JSONObject().put("type", "chat").put("text", text)) },
                    )
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
    } // JamboreeTheme
}

@Composable
private fun SlatePerson(name: String, role: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Avatar(name, host = role == "President", size = 40.dp)
        MonoLabel(role, size = 9, color = Ub.Accent)
        Text(name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
    }
}

@Composable
private fun Tracks(s: SecretHitlerGuestState) {
    SHTrackView("Liberal track", s.liberalPolicies, 5, Sh.Liberal, "★")
    Spacer(Modifier.height(8.dp))
    SHTrackView("Fascist track", s.fascistPolicies, 6, Sh.Fascist, "✖")
    Spacer(Modifier.height(8.dp))
    Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        MonoLabel("Election tracker")
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (i in 0 until 3) {
                Box(Modifier.weight(1f).height(16.dp).clip(RoundedCornerShape(4.dp))
                    .background(if (i < s.electionTracker) Ub.Accent else Color.White.copy(alpha = 0.06f))
                    .border(1.dp, Ub.LineStrong, RoundedCornerShape(4.dp)))
            }
        }
        MonoLabel("${s.electionTracker}/3", size = 9, color = Ub.Faint)
    }
}

@Composable
private fun SHTrackView(title: String, filled: Int, max: Int, color: Color, glyph: String) {
    val ink = if (color == Sh.Liberal) Sh.LiberalInk else Sh.FascistInk
    Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row,
            fill = color.copy(alpha = 0.10f), stroke = color.copy(alpha = 0.45f))
        .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MonoLabel(title, size = 10, color = color)
            Spacer(Modifier.weight(1f))
            MonoLabel("$filled/$max", size = 9, color = Ub.Faint)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (i in 0 until max) {
                val on = i < filled
                Box(Modifier.weight(1f).height(30.dp).clip(RoundedCornerShape(4.dp))
                    .background(if (on) color else Color.White.copy(alpha = 0.04f)),
                    contentAlignment = Alignment.Center) {
                    Text(if (on) glyph else "${i + 1}", fontSize = 13.sp, fontWeight = FontWeight.ExtraBold,
                         color = if (on) ink else Color.White.copy(alpha = 0.18f))
                }
            }
        }
    }
}

@Composable
private fun SHPolicyView(team: String, width: Dp) {
    val isLib = team == "L"
    val color = if (isLib) Sh.Liberal else Sh.Fascist
    val ink = if (isLib) Sh.LiberalInk else Sh.FascistInk
    Column(Modifier.width(width).height(width * 1.4f).clip(RoundedCornerShape(6.dp))
        .background(color).border(1.dp, Color.Black.copy(alpha = 0.3f), RoundedCornerShape(6.dp)),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center) {
        Text(if (isLib) "★" else "✖", fontSize = (width.value * 0.4f).sp, fontWeight = FontWeight.ExtraBold, color = ink)
        MonoLabel(if (isLib) "Liberal" else "Fascist", size = 8, color = ink.copy(alpha = 0.7f))
    }
}

@Composable
private fun RoleCard(s: SecretHitlerGuestState) {
    val role = s.role ?: return
    val m = roleMetaSh(role)
    Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel,
            fill = m.color.copy(alpha = 0.12f), stroke = m.color.copy(alpha = 0.45f))
        .padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(52.dp).clip(RoundedCornerShape(13.dp)).background(m.color),
                contentAlignment = Alignment.Center) {
                Text(m.glyph, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = m.ink)
            }
            Column {
                MonoLabel("You are · team ${m.team}", size = 9, color = m.color)
                Text(m.name, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1).sp,
                     color = Ub.Foreground)
            }
        }
        Text(m.blurb, fontSize = 13.sp, color = Ub.Muted)
        if (s.allies.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                MonoLabel("You know", size = 9)
                for (ally in s.allies) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(ally.name, size = 24.dp)
                        Spacer(Modifier.width(10.dp))
                        Text(ally.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
                        Spacer(Modifier.weight(1f))
                        MonoLabel(if (ally.role == "hitler") "Hitler" else "Fascist", size = 9,
                                  color = if (ally.role == "hitler") Color.White else Sh.Fascist)
                    }
                }
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
            if (amPresident) PickList("Nominate a Chancellor",
                s.players.filter { it.id in s.eligibleChancellors }) { p ->
                ctx.client.send(JSONObject().put("type", "nominate").put("targetId", p.id))
            } else Waiting("${s.playerName(s.presidentId)} is nominating a Chancellor")
        }
        "election" -> {
            if (!meAlive) Waiting("Watching from the sidelines")
            else if (s.voted) Waiting("Vote locked in · ${s.voteProgress}/${s.voteTotal} voted")
            else {
                MonoLabel("Vote on the government")
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    VoteButton("JA!", "YES", Sh.Liberal, Sh.LiberalInk, Modifier.weight(1f)) {
                        ctx.client.send(JSONObject().put("type", "vote").put("ja", true)); s.voted = true
                    }
                    VoteButton("NEIN!", "NO", Sh.Fascist, Sh.FascistInk, Modifier.weight(1f)) {
                        ctx.client.send(JSONObject().put("type", "vote").put("ja", false)); s.voted = true
                    }
                }
                MonoLabel("${s.voteProgress}/${s.voteTotal} voted", size = 9, color = Ub.Faint)
            }
        }
        "presidentDiscard" -> {
            if (amPresident && s.presidentialHand != null)
                PolicyChoice("Discard one — two go to the Chancellor", s.presidentialHand!!, "Discard") { i ->
                    ctx.client.send(JSONObject().put("type", "discard").put("index", i))
                }
            else Waiting("${s.playerName(s.presidentId)} is discarding")
        }
        "chancellorEnact" -> {
            if (amChancellor && s.chancellorHand != null) {
                PolicyChoice("Enact one policy", s.chancellorHand!!, "Enact") { i ->
                    ctx.client.send(JSONObject().put("type", "enact").put("index", i))
                }
                if (s.vetoUnlocked) UbSecondaryButton("Request veto",
                    onClick = { ctx.client.send(JSONObject().put("type", "request_veto")) })
            } else Waiting("${s.playerName(s.chancellorId)} is enacting")
        }
        "vetoDecision" -> {
            if (amPresident) {
                MonoLabel("Chancellor wants to veto")
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    UbPrimaryButton("Agree — veto", modifier = Modifier.weight(1f),
                        onClick = { ctx.client.send(JSONObject().put("type", "veto_response").put("confirm", true)) })
                    UbSecondaryButton("Refuse", modifier = Modifier.weight(1f),
                        onClick = { ctx.client.send(JSONObject().put("type", "veto_response").put("confirm", false)) })
                }
            } else Waiting("Veto requested — ${s.playerName(s.presidentId)} is deciding")
        }
        "policyPeek" -> {
            if (amPresident && s.peekedPolicies != null) {
                MonoLabel("Top three policies")
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (p in s.peekedPolicies!!) SHPolicyView(if (p == "liberal") "L" else "F", 72.dp)
                }
                UbPrimaryButton("Done", onClick = { ctx.client.send(JSONObject().put("type", "ack_peek")) })
            } else Waiting("${s.playerName(s.presidentId)} is peeking at the deck")
        }
        "investigation" -> {
            if (amPresident) PickList("Investigate a player's party",
                s.players.filter { it.alive && it.id != s.presidentId && it.id !in s.investigatedIds }) { p ->
                ctx.client.send(JSONObject().put("type", "investigate").put("targetId", p.id))
            } else Waiting("${s.playerName(s.presidentId)} is investigating")
        }
        "investigationReveal" -> {
            if (amPresident && s.investigationResult != null) {
                val inv = s.investigationResult!!
                Column(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.panel).padding(16.dp),
                       verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    MonoLabel("Investigation", color = Ub.Accent)
                    Text("${s.playerName(inv.subjectId)} is ${inv.party.replaceFirstChar { it.uppercase() }}",
                         fontSize = 20.sp, fontWeight = FontWeight.ExtraBold,
                         color = if (inv.party == "fascist") Sh.Fascist else Sh.Liberal)
                    Text("Share it or lie about it.", fontSize = 13.sp, color = Ub.Muted)
                    UbPrimaryButton("Done", onClick = { ctx.client.send(JSONObject().put("type", "ack_investigation")) })
                }
            } else Waiting("${s.playerName(s.presidentId)} has the investigation result")
        }
        "specialElection" -> {
            if (amPresident) PickList("Pick the next President",
                s.players.filter { it.alive && it.id != s.presidentId }) { p ->
                ctx.client.send(JSONObject().put("type", "special_election").put("targetId", p.id))
            } else Waiting("${s.playerName(s.presidentId)} is calling a special election")
        }
        "execution" -> {
            if (amPresident) PickList("Execute a player",
                s.players.filter { it.alive && it.id != s.presidentId }) { p ->
                ctx.client.send(JSONObject().put("type", "execute").put("targetId", p.id))
            } else Waiting("${s.playerName(s.presidentId)} is choosing someone to execute")
        }
    }
}

@Composable
private fun VoteButton(title: String, sub: String, color: Color, ink: Color, modifier: Modifier, onClick: () -> Unit) {
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(color).clickable(onClick = onClick)
        .padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = ink)
        MonoLabel(sub, size = 9, color = ink.copy(alpha = 0.7f))
    }
}

@Composable
private fun PickList(title: String, players: List<SecretHitlerGuestState.Player>,
                     action: (SecretHitlerGuestState.Player) -> Unit) {
    MonoLabel(title)
    for (p in players) {
        Row(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row).clickable { action(p) }
            .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Avatar(p.name, size = 28.dp)
            Spacer(Modifier.width(12.dp))
            Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ub.Foreground)
            Spacer(Modifier.weight(1f))
            Text("›", fontSize = 18.sp, color = Ub.Faint)
        }
    }
}

@Composable
private fun PolicyChoice(title: String, hand: List<String>, verb: String, action: (Int) -> Unit) {
    MonoLabel(title)
    Row(Modifier.fillMaxWidth().ubCard().padding(vertical = 14.dp),
        horizontalArrangement = Arrangement.Center) {
        hand.forEachIndexed { i, pol ->
            Column(Modifier.clickable { action(i) }.padding(horizontal = 7.dp),
                   horizontalAlignment = Alignment.CenterHorizontally,
                   verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SHPolicyView(if (pol == "liberal") "L" else "F", 80.dp)
                MonoLabel(verb, size = 9, color = if (pol == "liberal") Sh.Liberal else Sh.Fascist)
            }
        }
    }
}

@Composable
private fun Waiting(msg: String) {
    Box(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.row).padding(horizontal = 16.dp, vertical = 14.dp)) {
        Text("$msg…", fontSize = 14.sp, color = Ub.Muted)
    }
}

private object Sh {
    val Liberal = Color(0xFF4F9EFF)
    val LiberalInk = Color(0xFF02152E)
    val Fascist = Color(0xFFFF5A4A)
    val FascistInk = Color(0xFF3A0A04)
    val Hitler = Color(0xFF0E0E10)
}

private data class ShRoleMeta(val name: String, val team: String, val blurb: String,
                              val glyph: String, val color: Color, val ink: Color)

private fun roleMetaSh(role: String): ShRoleMeta = when (role) {
    "liberal" -> ShRoleMeta("Liberal", "Liberals",
        "Enact 5 Liberal policies — or have Hitler executed. You don't know who anyone else is.",
        "★", Sh.Liberal, Sh.LiberalInk)
    "fascist" -> ShRoleMeta("Fascist", "Fascists",
        "Enact 6 Fascist policies — or sneak Hitler in as Chancellor after 3.",
        "✖", Sh.Fascist, Sh.FascistInk)
    "hitler" -> ShRoleMeta("Hitler", "Fascists",
        "You are also a Fascist. Stay hidden — if elected Chancellor after 3 fascist policies, you win.",
        "✠", Sh.Hitler, Color.White)
    else -> ShRoleMeta(role.replaceFirstChar { it.uppercase() }, "—", role, "•", Sh.Liberal, Sh.LiberalInk)
}

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
    var chat by mutableStateOf<List<TeamChatMessage>>(emptyList())
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
            "chat" -> {
                val text = m.optString("text")
                if (text.isNotEmpty()) chat = chat + TeamChatMessage(
                    java.util.UUID.randomUUID().toString(),
                    m.optString("fromId"), m.optString("fromName"), text)
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
