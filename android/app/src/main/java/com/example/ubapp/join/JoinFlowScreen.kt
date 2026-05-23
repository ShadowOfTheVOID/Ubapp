package com.example.ubapp.join

import android.app.Activity
import android.view.WindowManager
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
import com.example.ubapp.theme.MonoLabel
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.UbPrimaryButton
import com.example.ubapp.theme.UbSecondaryButton
import com.example.ubapp.theme.ubCard
import com.example.ubapp.games.bluffmarket.BluffMarketGuestScreen
import com.example.ubapp.games.cheat.CheatGuestScreen
import com.example.ubapp.games.codenames.CodenamesGuestScreen
import com.example.ubapp.games.crazyeights.CrazyEightsGuestScreen
import com.example.ubapp.games.imposter.ImposterGuestScreen
import com.example.ubapp.games.president.PresidentGuestScreen
import com.example.ubapp.games.mafia.MafiaGuestScreen
import com.example.ubapp.games.secrethitler.SecretHitlerGuestScreen
import com.example.ubapp.games.werewolf.WerewolfGuestScreen
import com.example.ubapp.theme.UbappTheme
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

    DisposableEffect(Unit) {
        // Keep the screen awake while joined so the device's inactivity
        // timeout can't sleep the screen, drop the socket and kick us.
        (ctx as? Activity)?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            (ctx as? Activity)?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            client?.close()
        }
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
            "tag" -> com.example.ubapp.games.tag.TagGuestScreen(ctx)
            else -> Text("Unknown game: $game")
        }
        return
    }

    UbappTheme {
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
            Text("Or paste the IP shown under the host's QR.", fontSize = 12.sp, color = Ub.Muted)
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
                        status = "Couldn't read that — enter the 7-character code or the IP."
                        return@Button
                    }
                    val url = "wss://$ip:${JoinCode.DEFAULT_PORT}/ws"
                    val gc = GuestClient(url, ctx)
                    // Drop the live client and fall back to the join form,
                    // surfacing `message`. Guarded on `client` so the
                    // re-entrant CLOSED that close() emits is a no-op instead
                    // of recursing, and so a later CLOSED can't overwrite a
                    // FAILED message with the generic one.
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
                            // Stop consuming here. Everything after `welcome`
                            // now buffers inside the client until the
                            // per-game screen attaches its handler — closing
                            // the hand-off gap that dropped those frames.
                            gc.onMessage = null
                        } else if (welcomedGame == null && type == "error") {
                            // A host that rejects this client before any
                            // welcome (e.g. Tag, which speaks its own
                            // proximity protocol) sends an `error`. Surface
                            // it instead of hanging on the spinner.
                            failBack(msg.optString("message", "Host refused the connection."))
                        } else {
                            queued.add(msg)
                        }
                    }
                    gc.connect()
                    status = ""
                    client = gc
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
