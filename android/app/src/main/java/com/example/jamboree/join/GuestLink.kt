package com.example.jamboree.join

import android.os.Handler
import android.os.Looper
import com.example.jamboree.social.HostServer
import org.json.JSONObject

/**
 * Transport abstraction shared by every per-game player screen. The screen
 * the host sees is now the *same* player screen guests see; only the wire
 * underneath differs:
 *
 *  - [GuestClient] — a real WebSocket to a remote host phone.
 *  - [LoopbackGuest] — an in-process pipe straight into the host's own
 *    [HostServer], so the host plays as a normal player on the same screen.
 */
interface GuestLink {
    var onMessage: ((JSONObject) -> Unit)?
    fun send(payload: JSONObject)
}

/**
 * In-process [GuestLink] bound to the host's own [HostServer]. The host is
 * added to its game's engine as the `host` player; this pipe carries the
 * exact JSON a remote guest would exchange, so the host renders the identical
 * player screen and acts through the same code path.
 *
 * Messages emitted before the player screen mounts (lobby roster, options,
 * the phase/role burst from "Start round") are buffered and flushed the
 * moment the screen attaches its [onMessage] handler — the same guarantee
 * `JoinFlowScreen` gives remote guests via its replay queue.
 */
class LoopbackGuest(private val server: HostServer) : GuestLink {
    val guestId: GuestId = server.localGuestId ?: server.attachLocalGuest()

    private val mainHandler = Handler(Looper.getMainLooper())
    private val buffer = ArrayList<JSONObject>()

    override var onMessage: ((JSONObject) -> Unit)? = null
        set(value) {
            field = value
            if (value != null) flush()
        }

    init {
        server.onLocalSend = { raw ->
            val obj = runCatching { JSONObject(raw) }.getOrNull()
            if (obj != null) post { deliver(obj) }
        }
    }

    private fun deliver(msg: JSONObject) {
        val cb = onMessage
        if (cb != null) cb(msg) else buffer.add(msg)
    }

    private fun flush() {
        val pending = ArrayList(buffer)
        buffer.clear()
        for (m in pending) onMessage?.invoke(m)
    }

    override fun send(payload: JSONObject) {
        server.injectFromLocal(payload.toString())
    }

    private fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block()
        else mainHandler.post(block)
    }
}
