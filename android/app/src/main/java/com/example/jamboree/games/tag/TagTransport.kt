package com.example.jamboree.games.tag

import com.example.jamboree.join.GuestLink
import com.example.jamboree.social.GuestId
import com.example.jamboree.social.HostServer
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

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
    /** peerId → chosen display name, learned from the join handshake and the
     *  peer's `hello`. The lobby uses this so peers show their real name. */
    private val peerDisplayNames = HashMap<String, String>()

    override var onInbound: ((TagMessage) -> Unit)? = null
    override var onPeerConnected: ((String) -> Unit)? = null
    override var onPeerDisconnected: ((String) -> Unit)? = null

    fun displayName(peerId: String): String = peerDisplayNames[peerId] ?: peerId

    /** Whether a peer-originated message is allowed from [sender] (the peerId
     *  bound to that connection at `hello`/join). `Tag`/`Unfreeze`/
     *  `TutorialVote` are only honored when the actor id matches the sender;
     *  `Start`/`End`/`TutorialState` are host-authoritative and never accepted
     *  from a peer. `Hello` is handled before this check. */
    private fun isAuthentic(msg: TagMessage, sender: String?): Boolean = when (msg) {
        is TagMessage.Tag -> sender != null && msg.taggerId == sender
        is TagMessage.Unfreeze -> sender != null && msg.unfreezerId == sender
        is TagMessage.TutorialVote -> sender != null && msg.voterId == sender
        is TagMessage.TutorialCall -> true
        is TagMessage.Start, is TagMessage.End,
        is TagMessage.TutorialState, is TagMessage.Hello -> false
    }

    init {
        server.onJoin = { g -> onPeerConnected?.invoke(g.value) }
        server.onLeave = { g ->
            guestToPeer.remove(g)?.let {
                peerDisplayNames.remove(it)
                onPeerDisconnected?.invoke(it)
            }
        }
        server.onMessage = { g, raw ->
            val msg = runCatching { TagMessage.decode(raw) }.getOrNull()
            if (msg != null) {
                if (msg is TagMessage.Hello) {
                    guestToPeer[g] = msg.peerId
                    peerDisplayNames[msg.peerId] = msg.displayName
                    onInbound?.invoke(msg)  // hello is not relayed to other peers
                } else if (isAuthentic(msg, guestToPeer[g])) {
                    onInbound?.invoke(msg)
                    // Echo to other peers. The host's own TagSession already
                    // applied any state change locally.
                    server.broadcast(raw)
                }
                // Else: a spoofed actor or a peer-forged round-control/state
                // message. The host is the authoritative relay, so drop it
                // here — it is neither applied on the host nor echoed, so no
                // peer can tag/unfreeze on behalf of another player or end the
                // round with an arbitrary winner.
            } else {
                // Not a TagMessage — the browser-tier "Join a game"
                // handshake. App peers join Tag by code: complete the
                // handshake so the generic flow can mount the native Tag
                // peer screen, then the peer speaks TagMessages over this
                // same socket.
                val j = runCatching { JSONObject(raw) }.getOrNull()
                if (j?.optString("type") == "join") {
                    val name = j.optString("name").trim()
                    val peerId = g.value
                    guestToPeer[g] = peerId
                    peerDisplayNames[peerId] = name.ifEmpty { peerId }
                    server.send(g, JSONObject()
                        .put("type", "welcome").put("game", "tag")
                        .put("yourId", peerId).put("yourName", name).toString())
                } else {
                    server.disconnect(g,
                        """{"type":"error","message":"This host is running Tag — open it in the app to join."}""")
                }
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

/**
 * App-peer transport that rides the browser-tier [GuestLink] socket the
 * generic "Join a game" flow already opened, rather than dialing a second
 * raw WebSocket. Tag messages travel as the same JSON every other game uses.
 */
class GuestLinkTagTransport(private val client: GuestLink) : TagTransport {
    override var onInbound: ((TagMessage) -> Unit)? = null
    override var onPeerConnected: ((String) -> Unit)? = null
    override var onPeerDisconnected: ((String) -> Unit)? = null

    /** Subscribe to the socket. Call this *after* the owning [TagSession]
     *  has set [onInbound]: assigning [GuestLink.onMessage] synchronously
     *  flushes frames buffered since `welcome`, which would otherwise
     *  arrive before the session is wired. */
    fun start() {
        client.onMessage = { j ->
            runCatching { TagMessage.decode(j) }.getOrNull()?.let { onInbound?.invoke(it) }
        }
    }

    override fun send(msg: TagMessage) { client.send(msg.toJson()) }
    override fun dispose() { client.onMessage = null }
}

/** Local-only transport for single-device dev mode. */
class LoopbackTagTransport : TagTransport {
    override var onInbound: ((TagMessage) -> Unit)? = null
    override var onPeerConnected: ((String) -> Unit)? = null
    override var onPeerDisconnected: ((String) -> Unit)? = null
    override fun send(msg: TagMessage) { onInbound?.invoke(msg) }
    override fun dispose() {}
}
