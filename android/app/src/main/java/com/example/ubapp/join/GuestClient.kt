package com.example.ubapp.join

import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * WebSocket client used by app guests to join a host phone running the
 * in-app server. Built on OkHttp — already on the classpath for Tag peers.
 * Callbacks fire on the main thread so Compose state writes are safe.
 */
class GuestClient(private val url: String) {
    enum class StateKind { CONNECTING, OPEN, CLOSED, FAILED }
    data class State(val kind: StateKind, val message: String? = null)

    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .build()
    private var ws: WebSocket? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile var state: State = State(StateKind.CONNECTING); private set

    var onStateChange: ((State) -> Unit)? = null
    /** Each frame received from the server, parsed as a JSONObject. Fires on the main thread. */
    var onMessage: ((JSONObject) -> Unit)? = null

    fun connect() {
        val req = Request.Builder().url(url).build()
        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                post { update(State(StateKind.OPEN)) }
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = runCatching { JSONObject(text) }.getOrNull() ?: return
                post { onMessage?.invoke(obj) }
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                post { update(State(StateKind.CLOSED, reason)) }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                post { update(State(StateKind.FAILED, t.message)) }
            }
        })
    }

    fun send(payload: JSONObject) {
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
}
