package com.example.ubapp.games.mafia

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

@Composable
fun MafiaScreen() {
    val ctx = LocalContext.current
    val server = remember { MafiaServer(ctx) }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        server.onStateChange = { tick++ }
        onDispose { server.stop() }
    }

    val engine = server.engine
    @Suppress("UNUSED_EXPRESSION") tick  // re-read engine on every change

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (joinUrl == null) {
            Button(onClick = { joinUrl = server.start() }) { Text("Start hosting") }
        } else {
            ElevatedCard {
                Column(Modifier.padding(16.dp)) {
                    Text("Guests join here", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    QRCode(joinUrl!!, size = 220)
                    Text(joinUrl!!, style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        Text("Phase: ${engine.phase}  · Day ${engine.day}",
             style = MaterialTheme.typography.titleMedium)

        when (engine.phase) {
            MafiaPhase.LOBBY -> {
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Players (${engine.players.size})", style = MaterialTheme.typography.titleSmall)
                        for (p in engine.players.values.sortedBy { it.id }) {
                            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(p.name + if (p.isHost) " (host)" else "")
                            }
                        }
                    }
                }
                Button(onClick = { server.hostStart() }, enabled = engine.canStart) {
                    Text(if (engine.canStart) "Start round" else "Need 4+ players")
                }
            }
            MafiaPhase.NIGHT -> {
                val role = engine.players[MafiaServer.HOST_ID]?.role
                if (role != null) Text("Your role: ${role.displayName} — ${role.tagline}")
                if (role == MafiaRole.MAFIA || role == MafiaRole.DOCTOR) {
                    Text(if (role == MafiaRole.MAFIA) "Pick someone to kill"
                         else "Pick someone to save")
                    val targets = engine.alive.filter {
                        role == MafiaRole.DOCTOR || it.id != MafiaServer.HOST_ID
                    }
                    for (p in targets) {
                        OutlinedButton(
                            onClick = { server.hostNightAction(p.id) },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text(p.name) }
                    }
                } else {
                    Text("Waiting for mafia and doctor to act…")
                }
            }
            MafiaPhase.DAY_REVEAL -> {
                val n = engine.lastNight
                Text(when {
                    n?.killedId != null -> "${engine.players[n.killedId]?.name} was killed."
                    n?.savedId != null -> "The doctor saved someone — no one died."
                    else -> "A quiet night. No one died."
                })
                Button(onClick = { server.advanceFromReveal() }) { Text("Continue to day vote") }
            }
            MafiaPhase.DAY_VOTE -> {
                Text("Vote to eliminate")
                for (p in engine.alive.filter { it.id != MafiaServer.HOST_ID }) {
                    OutlinedButton(
                        onClick = { server.hostDayVote(p.id) },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(p.name) }
                }
                OutlinedButton(
                    onClick = { server.hostDayVote(null) },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Skip vote") }
            }
            MafiaPhase.GAME_OVER -> {
                Text(
                    if (engine.winner == MafiaWinner.TOWN) "Town wins" else "Mafia wins",
                    style = MaterialTheme.typography.headlineSmall,
                )
                for (p in engine.players.values) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(p.name); Text(p.role?.displayName ?: "—")
                    }
                }
            }
        }
    }
}

@Composable
private fun QRCode(text: String, size: Int) {
    val bitmap = remember(text, size) {
        val matrix = MultiFormatWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        for (x in 0 until size) for (y in 0 until size) {
            bmp.setPixel(x, y, if (matrix.get(x, y)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt())
        }
        bmp
    }
    Image(bitmap.asImageBitmap(), contentDescription = "QR code",
          modifier = Modifier.size(size.dp))
}
