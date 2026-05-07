package com.example.ubapp.social

/**
 * Slot for the offline multiplayer transport. Pick one (BLE / Wi-Fi Direct /
 * Nearby Connections / hotspot+mDNS) and implement this interface; the game
 * activities will use it without caring which one is plugged in.
 */
interface Transport {
    fun start(onPeer: (PeerId) -> Unit, onMessage: (PeerId, ByteArray) -> Unit)
    fun stop()
    fun send(to: PeerId, payload: ByteArray)
    fun broadcast(payload: ByteArray)

    @JvmInline value class PeerId(val raw: String)
}
