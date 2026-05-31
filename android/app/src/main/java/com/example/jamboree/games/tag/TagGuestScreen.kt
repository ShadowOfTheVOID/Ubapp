package com.example.ubapp.games.tag

import android.Manifest
import android.app.Activity
import android.view.WindowManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.ubapp.join.GuestContext
import com.example.ubapp.theme.UbappTheme
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.rememberMultiplePermissionsState

/**
 * Native screen an app peer sees after joining a Tag host by code via
 * "Join a game". Runs the same [TagSession] (mirror engine + BLE proximity)
 * the host runs, but its transport rides the [com.example.ubapp.join.GuestLink]
 * socket the join flow already opened. Foreground + screen-on for the round.
 */
@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun TagGuestScreen(gctx: GuestContext) {
    val androidCtx = LocalContext.current
    val perms = rememberMultiplePermissionsState(listOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_ADVERTISE,
        Manifest.permission.BLUETOOTH_CONNECT,
    ))

    var state by remember { mutableStateOf<TagState?>(null) }
    var advertiseStatus by remember { mutableStateOf("BLE idle.") }
    val ble = remember { mutableStateOf<BleProximityRuntime?>(null) }
    val session = remember { mutableStateOf<TagSession?>(null) }
    val transport = remember { mutableStateOf<GuestLinkTagTransport?>(null) }
    val selfId = gctx.yourId

    fun stopAll() {
        session.value?.dispose()
        ble.value?.stop()
        session.value = null; ble.value = null; transport.value = null
        (androidCtx as? Activity)?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
                Text("Playing as ${gctx.yourName}", style = MaterialTheme.typography.bodySmall)
                PermissionGate(perms) {
                    LaunchedEffect(Unit) {
                        if (session.value == null) {
                            val t = GuestLinkTagTransport(gctx.client)
                            val rt = BleProximityRuntime(androidCtx, selfId)
                            rt.onAdvertiseStatus = { s, err -> advertiseStatus = "BLE: $s ${err ?: ""}" }
                            // TagSession.init sets transport.onInbound;
                            // subscribe the socket only after, so buffered
                            // post-welcome frames aren't lost.
                            val sess = TagSession(selfId, gctx.yourName, rt, t)
                            sess.onStateChange = { s -> state = s }
                            ble.value = rt; session.value = sess; transport.value = t
                            t.start()
                            t.send(TagMessage.Hello(selfId, gctx.yourName))
                            (androidCtx as? Activity)?.window
                                ?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    val s = state
                    if (s == null) {
                        CircularProgressIndicator()
                        Text("Connected. Waiting for the host to begin the round…",
                             style = MaterialTheme.typography.bodyMedium)
                    } else {
                        RoundView(s, selfId,
                            onTag = { pid ->
                                val sess = session.value ?: return@RoundView
                                if (sess.engine.applyTag(selfId, pid)) {
                                    sess.transport.send(TagMessage.Tag(selfId, pid, System.currentTimeMillis()))
                                    state = sess.engine.state
                                }
                            },
                            onUnfreeze = { pid ->
                                val sess = session.value ?: return@RoundView
                                if (sess.engine.applyUnfreeze(selfId, pid)) {
                                    sess.transport.send(TagMessage.Unfreeze(selfId, pid, System.currentTimeMillis()))
                                    state = sess.engine.state
                                }
                            },
                            onBack = { stopAll() })
                    }
                    Text(advertiseStatus, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
