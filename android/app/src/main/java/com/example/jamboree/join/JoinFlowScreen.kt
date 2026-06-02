package com.example.jamboree.join

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.UbSecondaryButton
import com.example.jamboree.theme.ubCard
import com.example.jamboree.games.bluffmarket.BluffMarketGuestScreen
import com.example.jamboree.games.cheat.CheatGuestScreen
import com.example.jamboree.games.codenames.CodenamesGuestScreen
import com.example.jamboree.games.crazyeights.CrazyEightsGuestScreen
import com.example.jamboree.games.imposter.ImposterGuestScreen
import com.example.jamboree.games.president.PresidentGuestScreen
import com.example.jamboree.games.mafia.MafiaGuestScreen
import com.example.jamboree.games.bureaucrat.BureaucratGuestScreen
import com.example.jamboree.games.secrethitler.SecretHitlerGuestScreen
import com.example.jamboree.games.werewolf.WerewolfGuestScreen
import com.example.jamboree.theme.JamboreeTheme
import org.json.JSONObject

/** Bundle handed to a per-game guest screen. */
data class GuestContext(
    val client: GuestLink,
    val game: String,
    val yourId: String,
    val yourName: String,
    val replay: List<JSONObject>,
)

@Composable
fun JoinFlowScreen() {
    val ctx = LocalContext.current
    var rawCode by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var client by remember { mutableStateOf<GuestClient?>(null) }
    var welcomedGame by remember { mutableStateOf<String?>(null) }
    var yourId by remember { mutableStateOf<String?>(null) }
    var yourName by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("") }
    val queued = remember { mutableStateListOf<JSONObject>() }

    val discovery = remember { BonjourBrowser(ctx) }
    val mainHandler = remember { Handler(Looper.getMainLooper()) }

    DisposableEffect(Unit) {
        // Keep the screen awake while joined so the device's inactivity
        // timeout can't sleep the screen, drop the socket and kick us.
        (ctx as? Activity)?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        discovery.start()
        onDispose {
            (ctx as? Activity)?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            discovery.stop()
            client?.close()
        }
    }

    // Shared connect path for both the typed code/IP and a Bonjour-discovered
    // host. IPv6 literals are bracketed so the wss:// URL parses.
    fun connectTo(addr: String, port: Int) {
        val authority = if (addr.contains(':')) "[$addr]" else addr
        val url = "wss://$authority:$port/ws"
        val gc = GuestClient(url, ctx)
        fun failBack(message: String) {
            if (client == null) return
            val live = client
            client = null
            welcomedGame = null; yourId = null; yourName = null
            queued.clear()
            status = message
            live?.close()
        }
        gc.onStateChange = { s ->
            when (s.kind) {
                GuestClient.StateKind.OPEN ->
                    gc.send(JSONObject().put("type", "join").put("name", name.trim()))
                GuestClient.StateKind.FAILED ->
                    failBack("Connection failed: ${s.message ?: "unknown"}")
                GuestClient.StateKind.CLOSED ->
                    if (welcomedGame == null) failBack("Connection closed before joining.")
                else -> Unit
            }
        }
        gc.onMessage = { msg ->
            val type = msg.optString("type")
            if (type == "welcome" && msg.has("game")) {
                welcomedGame = msg.optString("game")
                yourId = msg.optString("yourId")
                yourName = msg.optString("yourName")
                gc.onMessage = null
            } else if (welcomedGame == null && type == "error") {
                failBack(msg.optString("message", "Host refused the connection."))
            } else {
                queued.add(msg)
            }
        }
        gc.connect()
        status = ""
        client = gc
    }

    val game = welcomedGame; val yid = yourId; val yn = yourName; val c = client
    if (c != null && game != null && yid != null && yn != null) {
        val ctx = remember(c, game, yid, yn) {
            GuestContext(c, game, yid, yn, queued.toList())
        }
        when (game) {
            "mafia" -> MafiaGuestScreen(ctx)
            "werewolf" -> WerewolfGuestScreen(ctx)
            "imposter" -> ImposterGuestScreen(ctx)
            "codenames" -> CodenamesGuestScreen(ctx)
            "crazy_eights" -> CrazyEightsGuestScreen(ctx)
            "cheat" -> CheatGuestScreen(ctx)
            "president" -> PresidentGuestScreen(ctx)
            "bluff_market" -> BluffMarketGuestScreen(ctx)
            "secret_hitler" -> SecretHitlerGuestScreen(ctx)
            "bureaucrat" -> BureaucratGuestScreen(ctx)
            "tag" -> com.example.jamboree.games.tag.TagGuestScreen(ctx)
            else -> Text("Unknown game: $game")
        }
        return
    }

    JamboreeTheme {
    Column(
        Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp),
    ) {
        if (client == null) {
            MonoLabel("Join", color = Ub.Accent)
            Spacer(Modifier.height(6.dp))
            Text("Enter the app code", fontSize = 30.sp, fontWeight = FontWeight.ExtraBold,
                 letterSpacing = (-0.9).sp, color = Ub.Foreground)
            Spacer(Modifier.height(6.dp))
            Text("The host's phone is showing it. Letters and numbers.",
                 fontSize = 13.sp, color = Ub.Muted)
            Spacer(Modifier.height(28.dp))

            MonoLabel("Your name")
            Spacer(Modifier.height(8.dp))
            FieldCard {
                BasicTextField(
                    value = name, onValueChange = { name = it }, singleLine = true,
                    textStyle = TextStyle(color = Ub.Foreground, fontSize = 16.sp),
                    cursorBrush = SolidColor(Ub.Accent),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                    decorationBox = { inner ->
                        if (name.isEmpty()) Text("Display name", color = Ub.Faint, fontSize = 16.sp)
                        inner()
                    },
                )
            }
            Spacer(Modifier.height(16.dp))

            // Bonjour-discovered hosts — tap one to join by name, no IP or
            // code. Only shown once a host is advertising on the network.
            if (discovery.hosts.isNotEmpty()) {
                MonoLabel("Nearby hosts")
                Spacer(Modifier.height(8.dp))
                discovery.hosts.forEach { host ->
                    Box(
                        Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.button)
                            .clickable {
                                if (name.isBlank()) {
                                    status = "Enter your name first."
                                    return@clickable
                                }
                                status = "Connecting to ${host.name}…"
                                discovery.resolve(host, onResolved = { addr, port ->
                                    mainHandler.post { connectTo(addr, port) }
                                }, onFailure = {
                                    mainHandler.post {
                                        status = "Couldn't reach ${host.name} — it may have stopped hosting."
                                    }
                                })
                            }
                            .padding(14.dp),
                    ) {
                        Text(host.name, color = Ub.Foreground, fontSize = 15.sp,
                             fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(Modifier.height(8.dp))
                }
                Spacer(Modifier.height(8.dp))
            }

            MonoLabel("App code")
            Spacer(Modifier.height(8.dp))
            FieldCard {
                BasicTextField(
                    value = rawCode, onValueChange = { rawCode = it }, singleLine = true,
                    textStyle = TextStyle(color = Ub.Foreground, fontSize = 22.sp,
                                          fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold,
                                          letterSpacing = 4.sp),
                    cursorBrush = SolidColor(Ub.Accent),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                    modifier = Modifier.fillMaxWidth(),
                    decorationBox = { inner ->
                        if (rawCode.isEmpty()) Text("ABCD-EFG", color = Ub.Faint, fontSize = 22.sp,
                                                    fontFamily = FontFamily.Monospace, letterSpacing = 4.sp)
                        inner()
                    },
                )
            }
            Spacer(Modifier.height(8.dp))
            Text("Pick the host above, or type the code from its screen.", fontSize = 12.sp, color = Ub.Muted)
            if (status.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Text(status, color = Ub.Accent, fontSize = 13.sp)
            }
            Spacer(Modifier.height(24.dp))
            UbPrimaryButton(
                "Connect",
                enabled = name.isNotBlank() && rawCode.isNotBlank(),
                onClick = {
                    val ip = JoinCode.decode(rawCode.trim())
                    if (ip == null) {
                        status = "Couldn't read that — check the 7-character code."
                        return@Button
                    }
                    connectTo(ip, JoinCode.DEFAULT_PORT)
                },
            )
        } else {
            Spacer(Modifier.height(40.dp))
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(color = Ub.Accent, strokeWidth = 2.dp,
                                          modifier = Modifier.size(20.dp))
                Text("Connecting…", fontSize = 15.sp, color = Ub.Muted)
            }
            if (status.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Text(status, color = Ub.Accent, fontSize = 13.sp)
            }
            Spacer(Modifier.height(20.dp))
            UbSecondaryButton("Cancel", onClick = {
                client?.close(); client = null
                welcomedGame = null; yourId = null; yourName = null
                queued.clear(); status = ""
            })
        }
    }
    }
}

@Composable
private fun FieldCard(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.button).padding(16.dp)) { content() }
}
