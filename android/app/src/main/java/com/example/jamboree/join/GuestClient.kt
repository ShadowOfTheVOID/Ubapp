package com.example.jamboree.join

import android.content.Context
import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/**
 * WebSocket client used by app guests to join a host phone running the
 * in-app server. Built on OkHttp — already on the classpath for Tag peers.
 * Callbacks fire on the main thread so Compose state writes are safe.
 *
 * Pass [ctx] so the client trusts the bundled self-signed server cert
 * (jamboree.p12). Without it the client falls back to the system trust store,
 * which rejects self-signed certs.
 */
class GuestClient(private val url: String, ctx: Context? = null) : GuestLink {
    enum class StateKind { CONNECTING, OPEN, CLOSED, FAILED }
    data class State(val kind: StateKind, val message: String? = null)

    private val client = buildOkHttp(ctx)
    private var ws: WebSocket? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile var state: State = State(StateKind.CONNECTING); private set

    var onStateChange: ((State) -> Unit)? = null

    private val inbox = ArrayList<JSONObject>()

    /**
     * Each frame received from the server, parsed as a JSONObject. Fires on
     * the main thread. Frames that arrive while no consumer is attached are
     * buffered and flushed the moment one is — mirroring [LoopbackGuest].
     * Without this, the lobby/options/phase frames the host sends right
     * after `welcome` land in the window between `JoinFlowScreen` handing
     * off and the per-game screen attaching, and are lost.
     */
    override var onMessage: ((JSONObject) -> Unit)? = null
        set(value) {
            field = value
            if (value != null) flushInbox()
        }

    private fun deliver(obj: JSONObject) {
        val cb = onMessage
        if (cb != null) cb(obj) else inbox.add(obj)
    }

    private fun flushInbox() {
        val pending = ArrayList(inbox)
        inbox.clear()
        for (m in pending) onMessage?.invoke(m)
    }

    fun connect() {
        val req = Request.Builder().url(url).build()
        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                post { update(State(StateKind.OPEN)) }
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = runCatching { JSONObject(text) }.getOrNull() ?: return
                post { deliver(obj) }
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                post { update(State(StateKind.CLOSED, reason)) }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                post { update(State(StateKind.FAILED, t.message)) }
            }
        })
    }

    override fun send(payload: JSONObject) {
        ws?.send(payload.toString())
    }

    fun close() {
        runCatching { ws?.close(1000, "guest left") }
        ws = null
        update(State(StateKind.CLOSED))
    }

    private fun update(s: State) { state = s; onStateChange?.invoke(s) }
    private fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block()
        else mainHandler.post(block)
    }

    companion object {
        private fun buildOkHttp(ctx: Context?): OkHttpClient {
            // A LAN host that isn't actually serving (wrong code, not
            // hosting, or a proximity-only game like Tag) should fail in
            // seconds, not read to the user as an endless "Connecting…".
            val base = OkHttpClient.Builder()
                .pingInterval(20, TimeUnit.SECONDS)
                .connectTimeout(10, TimeUnit.SECONDS)
            val tm = ctx?.let { pinningTrustManager(it) } ?: return base.build()
            val ssl = SSLContext.getInstance("TLS").also { it.init(null, arrayOf(tm), null) }
            return base
                .sslSocketFactory(ssl.socketFactory, tm)
                .hostnameVerifier { _, _ -> true }  // IP-based LAN; identity is pinned below
                .build()
        }

        /** Trusts exactly the bundled self-signed leaf certificate, by comparing
         *  the presented leaf's encoded bytes to the bundled cert's — matching
         *  the iOS `GuestClient` byte-pin. Stronger than trusting anything that
         *  chains to the bundled cert: since hostname verification is off for
         *  the dynamic LAN IP, identity must be the trust anchor. */
        private fun pinningTrustManager(ctx: Context): X509TrustManager? = runCatching {
            val ks = KeyStore.getInstance("PKCS12")
            ctx.assets.open("jamboree.p12").use { ks.load(it, "jamboree".toCharArray()) }
            val alias = ks.aliases().toList().firstOrNull { ks.getCertificate(it) != null }
            val pinned = ks.getCertificate(alias) as? X509Certificate ?: return@runCatching null
            val pinnedBytes = pinned.encoded
            object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                    val leaf = chain?.firstOrNull()
                        ?: throw CertificateException("no server certificate presented")
                    if (!leaf.encoded.contentEquals(pinnedBytes))
                        throw CertificateException("server certificate is not the pinned Jamboree cert")
                }
                override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf(pinned)
            }
        }.getOrNull()
    }
}
