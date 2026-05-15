package com.example.ubapp.join

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.example.ubapp.games.codenames.CodenamesGuestScreen
import com.example.ubapp.games.crazyeights.CrazyEightsGuestScreen
import com.example.ubapp.games.imposter.ImposterGuestScreen
import com.example.ubapp.games.mafia.MafiaGuestScreen
import com.example.ubapp.games.secrethitler.SecretHitlerGuestScreen
import com.example.ubapp.games.werewolf.WerewolfGuestScreen
import com.example.ubapp.theme.UbappTheme
import org.json.JSONObject

/** Bundle handed to a per-game guest screen. */
data class GuestContext(
    val client: GuestClient,
    val game: String,
    val yourId: String,
    val yourName: String,
    val replay: List<JSONObject>,
)

@Composable
fun JoinFlowScreen() {
    var rawCode by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var client by remember { mutableStateOf<GuestClient?>(null) }
    var welcomedGame by remember { mutableStateOf<String?>(null) }
    var yourId by remember { mutableStateOf<String?>(null) }
    var yourName by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("") }
    val queued = remember { mutableStateListOf<JSONObject>() }

    DisposableEffect(Unit) {
        onDispose { client?.close() }
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
            "secret_hitler" -> SecretHitlerGuestScreen(ctx)
            else -> Text("Unknown game: $game")
        }
        return
    }

    UbappTheme {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Join a game", style = MaterialTheme.typography.headlineSmall)
        if (client == null) {
            OutlinedTextField(
                value = name, onValueChange = { name = it },
                label = { Text("Your name") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
            )
            OutlinedTextField(
                value = rawCode, onValueChange = { rawCode = it },
                label = { Text("Join code or IP") },
                placeholder = { Text("ABCD-EFG") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
            Text("Ask the host for the code shown on their screen, or type the IP shown under the QR.",
                 style = MaterialTheme.typography.bodySmall)
            if (status.isNotEmpty()) Text(status, color = MaterialTheme.colorScheme.error,
                                          style = MaterialTheme.typography.bodySmall)
            Button(
                enabled = name.isNotBlank() && rawCode.isNotBlank(),
                onClick = {
                    val ip = JoinCode.decode(rawCode.trim())
                    if (ip == null) {
                        status = "Couldn't read that — enter the 7-character code or the IP."
                        return@Button
                    }
                    val url = "ws://$ip:${JoinCode.DEFAULT_PORT}/ws"
                    val gc = GuestClient(url)
                    gc.onStateChange = { s ->
                        when (s.kind) {
                            GuestClient.StateKind.OPEN ->
                                gc.send(JSONObject().put("type", "join").put("name", name.trim()))
                            GuestClient.StateKind.FAILED ->
                                status = "Connection failed: ${s.message ?: "unknown"}"
                            GuestClient.StateKind.CLOSED ->
                                if (welcomedGame == null) status = "Connection closed before joining."
                            else -> Unit
                        }
                    }
                    gc.onMessage = { msg ->
                        if (msg.optString("type") == "welcome" && msg.has("game")) {
                            welcomedGame = msg.optString("game")
                            yourId = msg.optString("yourId")
                            yourName = msg.optString("yourName")
                        } else {
                            queued.add(msg)
                        }
                    }
                    gc.connect()
                    status = ""
                    client = gc
                },
            ) { Text("Connect") }
        } else {
            CircularProgressIndicator()
            Text("Connecting…", style = MaterialTheme.typography.bodyMedium)
            if (status.isNotEmpty()) Text(status, color = MaterialTheme.colorScheme.error,
                                          style = MaterialTheme.typography.bodySmall)
            OutlinedButton(onClick = {
                client?.close(); client = null
                welcomedGame = null; yourId = null; yourName = null
                queued.clear(); status = ""
            }) { Text("Cancel") }
        }
    }
    }
}
