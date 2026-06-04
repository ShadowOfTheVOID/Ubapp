package com.example.jamboree.games.tag

data class ProximityEvent(val peerId: String, val rssi: Int, val atMs: Long)

/** Source of nearby-peer events. Production is BLE; tests can swap in
 *  [ManualProximity] which lets a UI button publish a fake event. */
interface ProximitySource {
    var onEvent: ((ProximityEvent) -> Unit)?
    fun start()
    fun stop()
}

/**
 * Sliding-window detector with hysteresis.
 *
 * Threshold note: phones brought together don't read like a clear-air
 * line-of-sight link — pressing two devices close shields the antennas with
 * each other's body/battery, so RSSI commonly sits around -65…-75 dBm rather
 * than the -40…-55 a clear link would suggest. An aggressive enter gate
 * (e.g. -55) therefore never fires when players actually touch phones, which
 * reads as "tag is broken". [enterDbm] matches the UI's "within a few metres"
 * promise; [exitDbm] trails it so a held-close pair stays "inside" without
 * re-firing.
 */
class ProximityDetector(
    val windowSize: Int = 4,
    val enterDbm: Int = -72,
    val exitDbm: Int = -82,
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

/** Stable service UUID used to identify Jamboree tag peers in BLE adverts and scans. */
const val JAMBOREE_TAG_SERVICE_UUID = "12340000-cafe-1337-1337-deadbeefcafe"
