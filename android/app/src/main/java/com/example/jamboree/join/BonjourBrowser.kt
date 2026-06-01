package com.example.jamboree.join

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import com.example.jamboree.social.HostServer

/**
 * Discovers Jamboree hosts on the local network via Bonjour
 * (`_jamboree._tcp`) so a guest can pick a host *by name* in the join flow
 * instead of typing an IP or app code. Pairs with the advertising side in
 * [HostServer], which registers the service on `startServer()`.
 *
 * Discovery yields service *names*; the concrete `host:port` is learned lazily
 * in [resolve] when the user taps one — NSD resolves one service at a time, so
 * resolving on tap (rather than for every found service) sidesteps the
 * "resolve already in progress" failure.
 */
class BonjourBrowser(context: Context) {
    data class Host(val name: String, val info: NsdServiceInfo)

    /** Discovered hosts, observed directly by Compose. */
    val hosts: SnapshotStateList<Host> = mutableStateListOf()

    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    fun start() {
        val nsd = nsd ?: return
        if (discoveryListener != null) return
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) {
                val name = info.serviceName ?: return
                if (hosts.none { it.name == name }) hosts.add(Host(name, info))
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                val name = info.serviceName ?: return
                hosts.removeAll { it.name == name }
            }
        }
        discoveryListener = listener
        runCatching {
            nsd.discoverServices(HostServer.SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        }
    }

    fun stop() {
        discoveryListener?.let { runCatching { nsd?.stopServiceDiscovery(it) } }
        discoveryListener = null
        hosts.clear()
    }

    /**
     * Resolves a discovered host to a concrete `(host, port)`. Calls [onResolved]
     * on success or [onFailure] if the host vanished. Callbacks fire on an NSD
     * binder thread — marshal to the main thread in the UI.
     */
    fun resolve(host: Host, onResolved: (host: String, port: Int) -> Unit, onFailure: () -> Unit) {
        val nsd = nsd ?: run { onFailure(); return }
        val listener = object : NsdManager.ResolveListener {
            override fun onServiceResolved(info: NsdServiceInfo) {
                val address = info.host?.hostAddress
                if (address != null) onResolved(address, info.port) else onFailure()
            }
            override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) = onFailure()
        }
        runCatching { nsd.resolveService(host.info, listener) }.onFailure { onFailure() }
    }
}
