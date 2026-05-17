package com.example.ubapp.social

import android.content.Context
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import java.net.NetworkInterface
import java.security.KeyStore
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext

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
    ctx: Context? = null,
) : NanoWSD(port) {

    private val sockets = HashMap<GuestId, GuestSocket>()
    private val nextId = AtomicInteger(0)
    private val sslFactory = ctx?.let { buildSslSocketFactory(it) }

    var onJoin: ((GuestId) -> Unit)? = null
    var onLeave: ((GuestId) -> Unit)? = null
    var onMessage: ((GuestId, String) -> Unit)? = null

    var hostIp: String? = null; private set

    /** The host plays as a normal player through an in-process pipe instead
     *  of a TCP socket. When set, [send]/[broadcast] deliver to this sink and
     *  [injectFromLocal] feeds frames back in as if received. */
    var localGuestId: GuestId? = null; private set
    var onLocalSend: ((String) -> Unit)? = null

    /** Registers the in-process host guest and returns its stable id. */
    fun attachLocalGuest(): GuestId {
        val id = GuestId("local")
        localGuestId = id
        onJoin?.invoke(id)
        return id
    }

    fun detachLocalGuest() {
        val id = localGuestId ?: return
        localGuestId = null
        onLeave?.invoke(id)
    }

    /** Feeds a frame into the server as if the host guest had sent it. */
    fun injectFromLocal(raw: String) {
        localGuestId?.let { onMessage?.invoke(it, raw) }
    }

    /** Returns the URL guests should open. null if no usable IPv4 (Wi-Fi,
     *  tethered hotspot, USB tether, or cellular) is available. */
    fun startServer(): String? {
        if (sslFactory != null) makeSecure(sslFactory, null)
        start(SOCKET_READ_TIMEOUT, false)
        hostIp = localIPv4()
        val scheme = if (sslFactory != null) "https" else "http"
        return hostIp?.let { "$scheme://$it:$port/" }
    }

    fun stopServer() {
        synchronized(sockets) {
            sockets.values.forEach { runCatching { it.close(WebSocketFrame.CloseCode.NormalClosure, "stop", false) } }
            sockets.clear()
        }
        localGuestId = null
        onLocalSend = null
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
        if (to == localGuestId) { onLocalSend?.invoke(payload); return }
        val ws = synchronized(sockets) { sockets[to] } ?: return
        runCatching { ws.send(payload) }
    }
    fun broadcast(payload: String) {
        val snapshot = synchronized(sockets) { sockets.values.toList() }
        for (ws in snapshot) runCatching { ws.send(payload) }
        localGuestId?.let { onLocalSend?.invoke(payload) }
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

        fun buildSslSocketFactory(ctx: Context): javax.net.ssl.SSLServerSocketFactory? =
            runCatching {
                val ks = KeyStore.getInstance("PKCS12")
                ctx.assets.open("ubapp.p12").use { ks.load(it, "ubapp".toCharArray()) }
                val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
                kmf.init(ks, "ubapp".toCharArray())
                val ssl = SSLContext.getInstance("TLS")
                ssl.init(kmf.keyManagers, null, null)
                ssl.serverSocketFactory
            }.getOrNull()

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
