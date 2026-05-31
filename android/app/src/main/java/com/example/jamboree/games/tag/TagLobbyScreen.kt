package com.example.ubapp.games.tag

import android.Manifest
import android.app.Activity
import android.view.WindowManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.shared.HostingChrome
import com.example.ubapp.social.HostServer
import com.example.ubapp.theme.UbappTheme
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.MultiplePermissionsState
import com.google.accompanist.permissions.rememberMultiplePermissionsState

/**
 * Tag lobby + round screen. The host phone runs a [HostServer],
 * [HostTagTransport], [BleProximityRuntime], and a [TagSession]. App peers
 * connect via WebSocket at the URL shown in the QR card.
 *
 * Runtime BLUETOOTH_SCAN + BLUETOOTH_ADVERTISE permissions are requested
 * before BLE can start. The activity's window is kept on while a round is
 * in flight — BLE peripheral advertising drops to a service-UUID-only
 * payload when backgrounded.
 */
@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun TagLobbyScreen() {
    val ctx = LocalContext.current
    val perms = rememberMultiplePermissionsState(listOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_ADVERTISE,
        Manifest.permission.BLUETOOTH_CONNECT,
    ))

    val server = remember { HostServer(html = HostServer.htmlAsset(ctx, "tag_browser.html"), ctx = ctx) }
    var hosting by remember { mutableStateOf(false) }
    var joinUrl by remember { mutableStateOf<String?>(null) }
    var variant by remember { mutableStateOf(TagVariant.CLASSIC) }
    var customDuration by remember { mutableStateOf(false) }
    var durationSec by remember { mutableIntStateOf(300) }
    var peers by remember { mutableStateOf<List<String>>(emptyList()) }
    var state by remember { mutableStateOf<TagState?>(null) }
    var advertiseStatus by remember { mutableStateOf("BLE idle.") }

    val transport = remember { mutableStateOf<HostTagTransport?>(null) }
    val ble = remember { mutableStateOf<BleProximityRuntime?>(null) }
    val session = remember { mutableStateOf<TagSession?>(null) }
    val selfId = "host"

    fun stopAll() {
        session.value?.dispose()
        ble.value?.stop()
        transport.value?.dispose()
        server.stopServer()
        session.value = null; ble.value = null; transport.value = null
        hosting = false; peers = emptyList(); state = null; joinUrl = null
        (ctx as? Activity)?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    DisposableEffect(Unit) { onDispose { stopAll() } }

    UbappTheme {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Column(
        Modifier
            .verticalScroll(rememberScrollState())
            .widthIn(max = 480.dp)
            .fillMaxWidth()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (!hosting) {
            Text("Tag — BLE proximity", style = MaterialTheme.typography.titleLarge)
            Text("Each phone advertises a BLE beacon and scans for others. Stay within a few metres to tag.",
                 style = MaterialTheme.typography.bodySmall)
            Text("Variant", style = MaterialTheme.typography.titleSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (v in TagVariant.entries) {
                    FilterChip(selected = variant == v, onClick = { variant = v },
                               label = { Text(v.displayName) })
                }
            }
            Text(variant.tagline, style = MaterialTheme.typography.bodySmall)
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Options", style = MaterialTheme.typography.titleSmall)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Switch(checked = customDuration, onCheckedChange = { customDuration = it })
                        Text("  Custom round length")
                    }
                    if (customDuration) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val m = durationSec / 60
                            val s = durationSec % 60
                            Text("Round: ${m}m ${s}s", Modifier.weight(1f))
                            IconButton(onClick = { durationSec = (durationSec - 30).coerceAtLeast(30) },
                                       enabled = durationSec > 30) {
                                Text("−", style = MaterialTheme.typography.titleLarge)
                            }
                            IconButton(onClick = { durationSec = (durationSec + 30).coerceAtMost(1800) },
                                       enabled = durationSec < 1800) {
                                Text("+", style = MaterialTheme.typography.titleLarge)
                            }
                        }
                        Text(
                            if (variant == TagVariant.HOT_POTATO)
                                "For Hot Potato this sets the per-tag countdown."
                            else "Replaces the default round length for the selected variant.",
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
            }

            PermissionGate(perms) {
                Button(onClick = {
                    joinUrl = server.startServer()
                    hosting = true
                    val t = HostTagTransport(server)
                    t.onPeerConnected = { pid -> peers = peers + pid }
                    t.onPeerDisconnected = { pid -> peers = peers - pid }
                    transport.value = t
                    (ctx as? Activity)?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }) { Text("Start hosting") }
            }
        } else if (state == null) {
            HostingChrome(
                joinUrl = joinUrl,
                onStart = { /* already started */ },
                onStop = { stopAll() },
            )
            Text(
                "App players join from \"Join a game\" using the code above. Everyone needs Bluetooth on and the app foregrounded.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("Connected peers (${peers.size + 1})",
                         style = MaterialTheme.typography.titleSmall)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("You (host)"); Text("ready", color = Color(0xFF2E7D32))
                    }
                    for (name in peers) Text(name)
                }
            }
            Text(advertiseStatus, style = MaterialTheme.typography.bodySmall)
            Button(
                enabled = peers.isNotEmpty(),
                onClick = {
                    val t = transport.value ?: return@Button
                    val rt = BleProximityRuntime(ctx, selfId)
                    rt.onAdvertiseStatus = { s, err -> advertiseStatus = "BLE: $s ${err ?: ""}" }
                    ble.value = rt
                    val sess = TagSession(selfId, "Host", rt, t, ctx.applicationContext)
                    sess.onStateChange = { s -> state = s }
                    val names = mutableMapOf(selfId to "Host")
                    for (p in peers) names[p] = t.displayName(p)
                    sess.startHosting(variant, names,
                                       durationOverrideSec = if (customDuration) durationSec else null)
                    session.value = sess
                },
            ) { Text("Begin round") }
        } else {
            RoundView(state!!, selfId,
                onTag = { peerId ->
                    val sess = session.value ?: return@RoundView
                    if (sess.engine.applyTag(selfId, peerId)) {
                        sess.transport.send(TagMessage.Tag(selfId, peerId, System.currentTimeMillis()))
                        state = sess.engine.state
                    }
                },
                onUnfreeze = { peerId ->
                    val sess = session.value ?: return@RoundView
                    if (sess.engine.applyUnfreeze(selfId, peerId)) {
                        sess.transport.send(TagMessage.Unfreeze(selfId, peerId, System.currentTimeMillis()))
                        state = sess.engine.state
                    }
                },
                onBack = { stopAll() })
        }
    }
    }
    }
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun PermissionGate(perms: MultiplePermissionsState, content: @Composable () -> Unit) {
    if (perms.allPermissionsGranted) content()
    else Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Tag needs Bluetooth scan + advertise permissions to detect nearby players.",
             style = MaterialTheme.typography.bodyMedium)
        Button(onClick = { perms.launchMultiplePermissionRequest() }) {
            Text("Grant Bluetooth permissions")
        }
    }
}

@Composable
fun RoundView(
    s: TagState, selfId: String,
    onTag: (String) -> Unit, onUnfreeze: (String) -> Unit, onBack: () -> Unit,
) {
    val me = s.players[selfId]
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(s.variant.displayName, style = MaterialTheme.typography.titleMedium)
            Text(s.variant.tagline, style = MaterialTheme.typography.bodySmall)
            if (me != null)
                Text("You are: ${statusLabel(me.status)}",
                     color = statusColor(me.status), style = MaterialTheme.typography.titleMedium)
            if (s.isOver) {
                Text(s.endReason ?: "Round over", style = MaterialTheme.typography.titleMedium)
                s.winnerId?.let { w ->
                    Text("Winner: ${s.players[w]?.displayName ?: w}",
                         color = Color(0xFF2E7D32))
                }
                Button(onClick = onBack) { Text("Back to lobby") }
            }
        }
    }

    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text("Players", style = MaterialTheme.typography.titleSmall)
            for (p in s.players.values.sortedBy { it.id }) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(p.displayName, modifier = Modifier.weight(1f))
                    Text(statusLabel(p.status), color = statusColor(p.status))
                    Spacer(Modifier.width(8.dp))
                    if (p.id != selfId && !s.isOver && me?.status == PlayerStatus.IT && p.status == PlayerStatus.RUNNER) {
                        OutlinedButton(onClick = { onTag(p.id) }) { Text("Tag") }
                    }
                    if (p.id != selfId && !s.isOver && s.variant == TagVariant.FREEZE
                        && me?.status == PlayerStatus.RUNNER && p.status == PlayerStatus.FROZEN) {
                        OutlinedButton(onClick = { onUnfreeze(p.id) }) { Text("Unfreeze") }
                    }
                }
            }
        }
    }
    Text("Manual tag/unfreeze buttons are a fallback for when BLE proximity isn't reliable.",
         style = MaterialTheme.typography.bodySmall)
}

private fun statusLabel(s: PlayerStatus) = when (s) {
    PlayerStatus.IT -> "IT"
    PlayerStatus.RUNNER -> "runner"
    PlayerStatus.FROZEN -> "frozen"
    PlayerStatus.ELIMINATED -> "out"
}
private fun statusColor(s: PlayerStatus) = when (s) {
    PlayerStatus.IT -> Color.Red
    PlayerStatus.RUNNER -> Color(0xFF2E7D32)
    PlayerStatus.FROZEN -> Color(0xFF0288D1)
    PlayerStatus.ELIMINATED -> Color.Gray
}
