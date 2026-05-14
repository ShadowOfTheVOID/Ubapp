package com.example.ubapp.games.tag

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import java.util.UUID

/**
 * Combined BLE central (scan) + peripheral (advertise) for one tag round.
 * Your phone sees other Ubapp peers AND advertises so others see you.
 *
 * Peer id is carried as a one-byte+UTF-8 service-data blob keyed by
 * [UBAPP_TAG_SERVICE_UUID]. On Android the adapter's name is also used as a
 * fallback for older OS versions where service data isn't honored.
 *
 * Callers must hold the runtime BLUETOOTH_SCAN / BLUETOOTH_ADVERTISE
 * permissions before calling [start] — the manifest already declares them.
 */
@SuppressLint("MissingPermission")
class BleProximityRuntime(
    context: Context,
    val selfPeerId: String,
    serviceUuid: String = UBAPP_TAG_SERVICE_UUID,
) : ProximitySource {
    enum class AdvertiseStatus { IDLE, STARTING, ADVERTISING, STOPPED, ERROR, UNAVAILABLE }

    override var onEvent: ((ProximityEvent) -> Unit)? = null
    var onAdvertiseStatus: ((AdvertiseStatus, String?) -> Unit)? = null

    private val serviceUuid = UUID.fromString(serviceUuid)
    private val parcelUuid = ParcelUuid(this.serviceUuid)
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = manager.adapter

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val rec = result.scanRecord ?: return
            val data = rec.serviceData?.get(parcelUuid)
            val peerId = data?.let { String(it).trim() } ?: rec.deviceName?.trim().orEmpty()
            if (peerId.isEmpty()) return
            onEvent?.invoke(ProximityEvent(peerId, result.rssi, System.currentTimeMillis()))
        }
        override fun onScanFailed(errorCode: Int) {
            onAdvertiseStatus?.invoke(AdvertiseStatus.ERROR, "scan failed: $errorCode")
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            onAdvertiseStatus?.invoke(AdvertiseStatus.ADVERTISING, null)
        }
        override fun onStartFailure(errorCode: Int) {
            onAdvertiseStatus?.invoke(AdvertiseStatus.ERROR, "advertise failed: $errorCode")
        }
    }

    override fun start() {
        val a = adapter ?: return onAdvertiseStatus?.invoke(AdvertiseStatus.UNAVAILABLE, "no BT adapter") ?: Unit
        if (!a.isEnabled) {
            onAdvertiseStatus?.invoke(AdvertiseStatus.UNAVAILABLE, "BT off"); return
        }

        a.bluetoothLeScanner?.startScan(
            listOf(ScanFilter.Builder().setServiceUuid(parcelUuid).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
            scanCallback,
        )

        val advertiser = a.bluetoothLeAdvertiser
        if (advertiser == null) {
            onAdvertiseStatus?.invoke(AdvertiseStatus.UNAVAILABLE, "advertiser unsupported"); return
        }
        onAdvertiseStatus?.invoke(AdvertiseStatus.STARTING, null)
        advertiser.startAdvertising(
            AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(false)
                .build(),
            AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(parcelUuid)
                .addServiceData(parcelUuid, selfPeerId.toByteArray())
                .build(),
            advertiseCallback,
        )
    }

    override fun stop() {
        adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        onAdvertiseStatus?.invoke(AdvertiseStatus.STOPPED, null)
    }
}
