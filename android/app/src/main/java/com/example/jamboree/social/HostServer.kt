package com.example.jamboree.social

import android.app.Activity
import android.app.Application
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.example.jamboree.ads.AdManager
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

    private val appCtx = ctx?.applicationContext
    private val sockets = HashMap<GuestId, GuestSocket>()
    private val nextId = AtomicInteger(0)
    private val sslFactory = ctx?.let { buildSslSocketFactory(it) }

    private fun dlog(s: String) = HostDiagnostics.log(s)

    var onJoin: ((GuestId) -> Unit)? = null
    var onLeave: ((GuestId) -> Unit)? = null
    var onMessage: ((GuestId, String) -> Unit)? = null

    var hostIp: String? = null; private set

    /** Display name advertised over Bonjour so app guests can discover this
     *  host by name in the join flow without typing an IP or app code. Defaults
     *  to the device's configured host name. */
    var serviceName: String? = null

    private val nsdManager = appCtx?.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private var nsdListener: NsdManager.RegistrationListener? = null

    /** Tears hosting down if the host app stays backgrounded this long, so
     *  socket guests don't sit in a dead game while the host is away. A
     *  brief background is fine — the timer is cancelled on return. */
    private val backgroundGraceMs = 300_000L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var startedActivities = 0
    private var backgroundStop: Runnable? = null
    private var lifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null
    @Volatile private var running = false

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
        appCtx?.let { com.example.jamboree.settings.AppSettings.diagnosticsEnabled(it) }
        if (sslFactory != null) makeSecure(sslFactory, null)
        start(SOCKET_READ_TIMEOUT, false)
        running = true
        observeAppLifecycle()
        hostIp = localIPv4()
        registerNsd()
        val scheme = if (sslFactory != null) "https" else "http"
        dlog("startServer: tls=${sslFactory != null} ip=$hostIp")
        return hostIp?.let { "$scheme://$it:$port/" }
    }

    /** Advertises this host over Bonjour (`_jamboree._tcp`). The NSD daemon
     *  fills in the address; guests browse for it in [BonjourBrowser]. */
    private fun registerNsd() {
        val nsd = nsdManager ?: return
        val name = serviceName
            ?: appCtx?.let { com.example.jamboree.settings.AppSettings.hostName(it) }
            ?: "Jamboree"
        val info = NsdServiceInfo().apply {
            serviceName = name
            serviceType = SERVICE_TYPE
            setPort(port)
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) =
                dlog("nsd registered as ${info.serviceName}")
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) =
                dlog("nsd registration failed: $errorCode")
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        }
        nsdListener = listener
        runCatching { nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener) }
            .onFailure { dlog("nsd registerService threw: $it") }
    }

    private fun unregisterNsd() {
        val nsd = nsdManager ?: return
        nsdListener?.let { runCatching { nsd.unregisterService(it) } }
        nsdListener = null
    }

    fun stopServer() {
        if (!running) return
        running = false
        unregisterNsd()
        cancelBackgroundStop()
        removeLifecycleObserver()
        val kicked = synchronized(sockets) {
            val snapshot = sockets.keys.toList()
            sockets.values.forEach { runCatching { it.close(WebSocketFrame.CloseCode.GoingAway, "stop", false) } }
            sockets.clear()
            snapshot
        }
        localGuestId = null
        onLocalSend = null
        // Fire onLeave deterministically. NanoWSD's onClose is async and
        // racy during shutdown, so games can't rely on it to drop the
        // kicked guests from the lobby/engine. onLeave handlers are
        // idempotent, so a late onClose is a harmless no-op.
        kicked.forEach { onLeave?.invoke(it) }
        stop()
    }

    private fun observeAppLifecycle() {
        val app = appCtx as? Application ?: return
        val cb = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) {
                startedActivities++
                cancelBackgroundStop()
            }
            override fun onActivityStopped(activity: Activity) {
                startedActivities--
                if (startedActivities <= 0) scheduleBackgroundStop()
            }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        }
        lifecycleCallbacks = cb
        app.registerActivityLifecycleCallbacks(cb)
    }

    private fun scheduleBackgroundStop() {
        cancelBackgroundStop()
        dlog("app backgrounded — will stop hosting in ${backgroundGraceMs / 1000}s if still away")
        val r = Runnable {
            dlog("background grace elapsed — stopping hosting")
            stopServer()
        }
        backgroundStop = r
        mainHandler.postDelayed(r, backgroundGraceMs)
    }

    private fun cancelBackgroundStop() {
        backgroundStop?.let { mainHandler.removeCallbacks(it) }
        backgroundStop = null
    }

    private fun removeLifecycleObserver() {
        lifecycleCallbacks?.let { (appCtx as? Application)?.unregisterActivityLifecycleCallbacks(it) }
        lifecycleCallbacks = null
    }

    override fun serveHttp(session: IHTTPSession): Response {
        dlog("serveHttp: ${session.method} ${session.uri}")
        // If the host owns the ad-free upgrade, suppress ads for the browser
        // guests this host serves by flagging the page before it loads.
        val adFree = appCtx?.let { AdManager.isAdFree(it) } ?: false
        val body = if (adFree)
            html.replaceFirst("</head>", "<script>window.UB_AD_FREE=true</script></head>")
        else html
        return newFixedLengthResponse(Response.Status.OK, "text/html; charset=utf-8", body)
    }

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        val id = GuestId("g${nextId.getAndIncrement()}")
        dlog("openWebSocket ${id.value}")
        return GuestSocket(id, handshake)
    }

    val guestCount: Int get() = synchronized(sockets) { sockets.size }
    val guests: List<GuestId> get() = synchronized(sockets) { sockets.keys.toList() }

    fun send(to: GuestId, payload: String) {
        if (to == localGuestId) { onLocalSend?.invoke(payload); return }
        val ws = synchronized(sockets) { sockets[to] }
        if (ws == null) {
            dlog("send ${to.value}: NO connection (lost) — ${payload.take(60)}")
            return
        }
        dlog("send ${to.value}: ${payload.length}B → ${payload.take(60)}")
        runCatching { ws.send(payload) }
    }
    fun broadcast(payload: String) {
        val snapshot = synchronized(sockets) { sockets.values.toList() }
        for (ws in snapshot) runCatching { ws.send(payload) }
        localGuestId?.let { onLocalSend?.invoke(payload) }
    }

    /** Sends a final payload to one guest, then drops the connection. Used to
     *  reject a client speaking the wrong protocol (e.g. the browser-tier
     *  join handshake hitting Tag) so it fails fast instead of hanging. */
    fun disconnect(to: GuestId, farewell: String? = null) {
        val ws = synchronized(sockets) { sockets.remove(to) } ?: return
        runCatching {
            if (farewell != null) ws.send(farewell)
            ws.close(WebSocketFrame.CloseCode.NormalClosure, "wrong protocol", false)
        }
        onLeave?.invoke(to)
    }

    private inner class GuestSocket(val id: GuestId, handshake: IHTTPSession) : WebSocket(handshake) {
        override fun onOpen() {
            synchronized(sockets) { sockets[id] = this }
            dlog("${id.value} onOpen → joined")
            onJoin?.invoke(id)
        }
        override fun onClose(code: WebSocketFrame.CloseCode?, reason: String?, initiatedByRemote: Boolean) {
            synchronized(sockets) { sockets.remove(id) }
            dlog("${id.value} onClose code=$code remote=$initiatedByRemote → leave")
            onLeave?.invoke(id)
        }
        override fun onMessage(message: WebSocketFrame) {
            val text = message.textPayload
            dlog("${id.value} rx ${text.length}B → ${text.take(80)}")
            onMessage?.invoke(id, text)
        }
        override fun onPong(pong: WebSocketFrame?) {}
        override fun onException(exception: java.io.IOException?) {
            synchronized(sockets) { sockets.remove(id) }
            dlog("${id.value} onException $exception → leave")
            onLeave?.invoke(id)
        }
    }

    companion object {
        /** Bonjour service type guests browse for to find hosts by name
         *  instead of IP. Keep in sync with the iOS `HostServer.bonjourType`. */
        const val SERVICE_TYPE = "_jamboree._tcp."

        const val defaultHtml = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>Jamboree guest</title>
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
                ctx.assets.open("jamboree.p12").use { ks.load(it, "jamboree".toCharArray()) }
                val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
                kmf.init(ks, "jamboree".toCharArray())
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
