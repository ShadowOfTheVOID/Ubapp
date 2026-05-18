package com.example.ubapp.games.tag

import com.example.ubapp.social.GuestId
import com.example.ubapp.social.HostServer
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/**
 * Bidirectional channel for tag messages. The host wraps its in-app
 * [HostServer]; each peer wraps a single outbound WebSocket to the host.
 */
interface TagTransport {
    var onInbound: ((TagMessage) -> Unit)?
    var onPeerConnected: ((String) -> Unit)?
    var onPeerDisconnected: ((String) -> Unit)?
    fun send(msg: TagMessage)
    fun dispose()
}

/** Host-side: wraps a running [HostServer]. */
class HostTagTransport(private val server: HostServer) : TagTransport {
    private val guestToPeer = HashMap<GuestId, String>()

    override var onInbound: ((TagMessage) -> Unit)? = null
    override var onPeerConnected: ((String) -> Unit)? = null
    override var onPeerDisconnected: ((String) -> Unit)? = null

    init {
        server.onJoin = { g -> onPeerConnected?.invoke(g.value) }
        server.onLeave = { g ->
            guestToPeer.remove(g)?.let { onPeerDisconnected?.invoke(it) }
        }
        server.onMessage = { g, raw ->
            val msg = runCatching { TagMessage.decode(raw) }.getOrNull()
            if (msg == null) {
                // Not a Tag peer — almost certainly the browser-tier
                // "Join a game" flow ({"type":"join"}). Tag is BLE-proximity
                // and has no code-join path, so reject it immediately rather
                // than leaving the guest stuck on "Connecting…".
                val err = """{"type":"error","message":"This host is running Tag. Tag uses Bluetooth proximity and can’t be joined with a code."}"""
                server.disconnect(g, err)
            } else {
                if (msg is TagMessage.Hello) guestToPeer[g] = msg.peerId
                onInbound?.invoke(msg)
                // Echo non-hello traffic back so other peers see it.
                if (msg !is TagMessage.Hello) server.broadcast(raw)
            }
        }
    }

    override fun send(msg: TagMessage) = server.broadcast(msg.encode())
    override fun dispose() = server.stopServer()
}

/** Peer-side: connects one WebSocket to the host. */
class PeerTagTransport private constructor(serverUrl: String) : TagTransport {
    private val client = OkHttpClient()
    private var ws: WebSocket? = null

    override var onInbound: ((TagMessage) -> Unit)? = null
    override var onPeerConnected: ((String) -> Unit)? = null
    override var onPeerDisconnected: ((String) -> Unit)? = null

    init {
        val req = Request.Builder().url(serverUrl).build()
        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching { onInbound?.invoke(TagMessage.decode(text)) }
            }
        })
    }

    companion object {
        /** Convert "https://host:port/" to "wss://host:port/ws" and connect. */
        fun connect(serverUrl: String): PeerTagTransport {
            val wsUrl = serverUrl
                .replaceFirst("https://", "wss://")
                .replaceFirst("http://", "ws://")
                .trimEnd('/') + "/ws"
            return PeerTagTransport(wsUrl)
        }
    }

    override fun send(msg: TagMessage) { ws?.send(msg.encode()) }
    override fun dispose() {
        ws?.close(1000, null); ws = null
        client.dispatcher.executorService.shutdown()
    }
}

/** Local-only transport for single-device dev mode. */
class LoopbackTagTransport : TagTransport {
    override var onInbound: ((TagMessage) -> Unit)? = null
    override var onPeerConnected: ((String) -> Unit)? = null
    override var onPeerDisconnected: ((String) -> Unit)? = null
    override fun send(msg: TagMessage) { onInbound?.invoke(msg) }
    override fun dispose() {}
}
