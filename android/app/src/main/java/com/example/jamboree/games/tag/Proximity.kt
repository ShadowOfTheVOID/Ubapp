package com.example.ubapp.games.tag

data class ProximityEvent(val peerId: String, val rssi: Int, val atMs: Long)

/** Source of nearby-peer events. Production is BLE; tests can swap in
 *  [ManualProximity] which lets a UI button publish a fake event. */
interface ProximitySource {
    var onEvent: ((ProximityEvent) -> Unit)?
    fun start()
    fun stop()
}

/** Sliding-window detector with hysteresis. */
class ProximityDetector(
    val windowSize: Int = 4,
    val enterDbm: Int = -55,
    val exitDbm: Int = -65,
    val immunityMs: Long = 2_000L,
    val onTouch: (String) -> Unit,
) {
    private val windows = HashMap<String, ArrayDeque<Int>>()
    private val inside = HashMap<String, Boolean>()
    private val immuneUntil = HashMap<String, Long>()

    fun grantImmunity(peerId: String) {
        immuneUntil[peerId] = System.currentTimeMillis() + immunityMs
    }

    fun ingest(event: ProximityEvent) {
        val w = windows.getOrPut(event.peerId) { ArrayDeque() }
        w.addLast(event.rssi)
        if (w.size > windowSize) w.removeFirst()
        val avg = w.sum().toDouble() / w.size

        val wasInside = inside[event.peerId] ?: false
        val isInside = if (wasInside) avg >= exitDbm else avg >= enterDbm
        inside[event.peerId] = isInside

        if (!wasInside && isInside) {
            val until = immuneUntil[event.peerId]
            if (until != null && System.currentTimeMillis() < until) return
            onTouch(event.peerId)
        }
    }

    fun reset() { windows.clear(); inside.clear(); immuneUntil.clear() }
}

/** Test source: emits whatever you push into it. */
class ManualProximity : ProximitySource {
    override var onEvent: ((ProximityEvent) -> Unit)? = null
    override fun start() {}
    override fun stop() {}
    fun push(peerId: String, rssi: Int = -45) {
        onEvent?.invoke(ProximityEvent(peerId, rssi, System.currentTimeMillis()))
    }
}

/** Stable service UUID used to identify Ubapp tag peers in BLE adverts and scans. */
const val UBAPP_TAG_SERVICE_UUID = "12340000-cafe-1337-1337-deadbeefcafe"
