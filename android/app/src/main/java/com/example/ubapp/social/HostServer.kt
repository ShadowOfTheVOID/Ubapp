package com.example.ubapp.social

import android.content.Context
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import java.net.NetworkInterface
import java.util.concurrent.atomic.AtomicInteger

/** Identifies one connected guest (browser tab or app instance) for the
 *  duration of the connection. Stable across messages from the same socket. */
@JvmInline value class GuestId(val value: String)

/**
 * One-tap host server. Spins up an HTTP listener on [port] (default 7654) and
 * upgrades requests at `/ws` to WebSocket. Everything else gets the
 * game-supplied landing HTML. Mirrors lib/social/host_server.dart.
 *
 * Built on NanoHTTPD-WebSocket so there's no Ktor footprint. Each connection
 * gets a stable [GuestId].
 */
class HostServer(
    val port: Int = 7654,
    var html: String = defaultHtml,
) : NanoWSD(port) {

    private val sockets = HashMap<GuestId, GuestSocket>()
    private val nextId = AtomicInteger(0)

    var onJoin: ((GuestId) -> Unit)? = null
    var onLeave: ((GuestId) -> Unit)? = null
    var onMessage: ((GuestId, String) -> Unit)? = null

    var hostIp: String? = null; private set

    /** Returns the URL guests should open. null if no usable IPv4 (Wi-Fi,
     *  tethered hotspot, USB tether, or cellular) is available. */
    fun startServer(): String? {
        start(SOCKET_READ_TIMEOUT, false)
        hostIp = localIPv4()
        return hostIp?.let { "http://$it:$port/" }
    }

    fun stopServer() {
        synchronized(sockets) {
            sockets.values.forEach { runCatching { it.close(WebSocketFrame.CloseCode.NormalClosure, "stop", false) } }
            sockets.clear()
        }
        stop()
    }

    override fun serveHttp(session: IHTTPSession): Response =
        newFixedLengthResponse(Response.Status.OK, "text/html; charset=utf-8", html)

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        val id = GuestId("g${nextId.getAndIncrement()}")
        return GuestSocket(id, handshake)
    }

    val guestCount: Int get() = synchronized(sockets) { sockets.size }
    val guests: List<GuestId> get() = synchronized(sockets) { sockets.keys.toList() }

    fun send(to: GuestId, payload: String) {
        val ws = synchronized(sockets) { sockets[to] } ?: return
        runCatching { ws.send(payload) }
    }
    fun broadcast(payload: String) {
        val snapshot = synchronized(sockets) { sockets.values.toList() }
        for (ws in snapshot) runCatching { ws.send(payload) }
    }

    private inner class GuestSocket(val id: GuestId, handshake: IHTTPSession) : WebSocket(handshake) {
        override fun onOpen() {
            synchronized(sockets) { sockets[id] = this }
            onJoin?.invoke(id)
        }
        override fun onClose(code: WebSocketFrame.CloseCode?, reason: String?, initiatedByRemote: Boolean) {
            synchronized(sockets) { sockets.remove(id) }
            onLeave?.invoke(id)
        }
        override fun onMessage(message: WebSocketFrame) {
            onMessage?.invoke(id, message.textPayload)
        }
        override fun onPong(pong: WebSocketFrame?) {}
        override fun onException(exception: java.io.IOException?) {
            synchronized(sockets) { sockets.remove(id) }
            onLeave?.invoke(id)
        }
    }

    companion object {
        const val defaultHtml = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>Ubapp guest</title>
          <style>
            body { font-family: -apple-system, system-ui, sans-serif; background:#0d1117; color:#e6edf3; margin:0; padding:24px; }
            .card { background:#161b22; padding:20px; border-radius:14px; max-width:480px; margin:auto; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>Connected.</h1>
            <p>Waiting for the host to start a game…</p>
          </div>
        </body>
        </html>
        """

        /** Loads a bundled HTML file from `assets/` (e.g. "mafia_browser.html"). */
        fun htmlAsset(ctx: Context, name: String): String =
            runCatching { ctx.assets.open(name).bufferedReader().use { it.readText() } }
                .getOrDefault(defaultHtml)

        /** Returns the device's best-candidate IPv4 address for guests to
         *  reach. Walks every up, non-loopback interface and prefers, in
         *  order:
         *    1. Wi-Fi (`wlan*`)
         *    2. Tethered hotspot soft-AP (`ap*`, `swlan*`) — host is sharing
         *       cellular over Wi-Fi
         *    3. USB / Ethernet tether (`rndis*`, `usb*`, `eth*`)
         *    4. Cellular (`rmnet*`, `ccmni*`, `pdp*`) — works for VPN/mesh
         *       peers; carrier NAT usually blocks direct guests
         *  Other names (vpn tunnels, dummy, p2p) are skipped. */
        fun localIPv4(): String? = runCatching {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { iface ->
                    iface.inetAddresses.toList()
                        .filter { !it.isLoopbackAddress && it.hostAddress?.contains(':') == false }
                        .mapNotNull { addr -> addr.hostAddress?.let { iface.name to it } }
                }
                .mapNotNull { (name, addr) -> ifacePriority(name)?.let { it to addr } }
                .minByOrNull { it.first }
                ?.second
        }.getOrNull()

        private fun ifacePriority(name: String): Int? = when {
            name.startsWith("wlan") -> 0
            name.startsWith("ap") || name.startsWith("swlan") -> 1
            name.startsWith("rndis") || name.startsWith("usb") || name.startsWith("eth") -> 2
            name.startsWith("rmnet") || name.startsWith("ccmni") || name.startsWith("pdp") -> 3
            else -> null
        }
    }
}
