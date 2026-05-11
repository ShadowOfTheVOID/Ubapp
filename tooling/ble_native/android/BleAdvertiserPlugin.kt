package com.example.ubapp

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Drop this file into the generated Android module after running
 * `flutter create .`. See tooling/ble_native/README.md for the wiring.
 *
 * Talks to BluetoothLeAdvertiser. Advertises a service UUID + the peer
 * id encoded in the local name field, which `flutter_blue_plus` reads as
 * `ScanResult.advertisementData.advName` on the scanner side.
 *
 * Permissions required (manifest):
 *   BLUETOOTH_ADVERTISE   (API 31+)
 *   BLUETOOTH_CONNECT     (API 31+ — required for some advertise paths)
 *   BLUETOOTH, BLUETOOTH_ADMIN  (API < 31)
 */
class BleAdvertiserPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var advertiser: BluetoothLeAdvertiser? = null
    private var callback: AdvertiseCallback? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "ubapp/ble_advertiser").also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, "ubapp/ble_advertiser/events").also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopAdvertising()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        context = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
    override fun onCancel(arguments: Any?) { eventSink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(getAdapter()?.isMultipleAdvertisementSupported == true)
            "requestPermissions" -> {
                // Activity-bound permission requests live in MainActivity; the
                // plugin just reports whether it could obtain the advertiser.
                result.success(getAdvertiser() != null)
            }
            "start" -> {
                val serviceUuid = call.argument<String>("serviceUuid")
                val peerId = call.argument<String>("peerId")
                if (serviceUuid == null || peerId == null) {
                    result.error("bad_args", "serviceUuid and peerId required", null)
                    return
                }
                try {
                    startAdvertising(serviceUuid, peerId)
                    result.success(null)
                } catch (e: SecurityException) {
                    emit("error", e.message)
                    result.error("permission", e.message, null)
                } catch (e: Exception) {
                    emit("error", e.message)
                    result.error("start_failed", e.message, null)
                }
            }
            "stop" -> {
                stopAdvertising()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun getAdapter(): BluetoothAdapter? {
        val mgr = context?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return mgr?.adapter
    }

    private fun getAdvertiser(): BluetoothLeAdvertiser? {
        val a = getAdapter() ?: return null
        return a.bluetoothLeAdvertiser
    }

    private fun startAdvertising(serviceUuid: String, peerId: String) {
        stopAdvertising()
        val adv = getAdvertiser() ?: run {
            emit("unavailable", "BluetoothLeAdvertiser not available")
            return
        }
        advertiser = adv
        emit("starting", null)

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .setTimeout(0)
            .build()

        val parcel = ParcelUuid(UUID.fromString(serviceUuid))
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(parcel)
            // Pack peer id into 16-byte ASCII service data; scanner pulls
            // either this or scan-response local name.
            .addServiceData(parcel, peerId.toByteArray(Charsets.UTF_8).take(16).toByteArray())
            .build()

        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()

        try {
            // Set the BluetoothAdapter local name to our peer id so iOS
            // scanners (which surface `peripheral.name`) can read it.
            getAdapter()?.let { adapter ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasConnectPermission()) {
                    adapter.name = peerId
                }
            }
        } catch (_: SecurityException) {
            // ignore — advertising still works, scanner falls back to service data
        }

        callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                emit("advertising", null)
            }
            override fun onStartFailure(errorCode: Int) {
                emit("error", "advertise failure code=$errorCode")
            }
        }
        adv.startAdvertising(settings, data, scanResponse, callback)
    }

    private fun stopAdvertising() {
        val adv = advertiser ?: return
        val cb = callback ?: return
        try {
            adv.stopAdvertising(cb)
        } catch (_: SecurityException) {}
        advertiser = null
        callback = null
        emit("stopped", null)
    }

    private fun hasConnectPermission(): Boolean {
        return try {
            val ctx = context ?: return false
            val pm = ctx.packageManager
            val info = pm.getPackageInfo(ctx.packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
            info.requestedPermissions?.contains("android.permission.BLUETOOTH_CONNECT") == true
        } catch (_: Exception) {
            false
        }
    }

    private fun emit(status: String, error: String?) {
        eventSink?.success(mapOf("status" to status, "error" to error))
    }
}
