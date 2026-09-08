package com.example.flashfloodcommunication.communication.ble

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED
import android.bluetooth.le.AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE
import android.bluetooth.le.AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED
import android.bluetooth.le.AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR
import android.bluetooth.le.AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.core.content.ContextCompat
import com.example.flashfloodcommunication.communication.core.AlertCodec
import com.example.flashfloodcommunication.communication.core.AlertPacket
import com.example.flashfloodcommunication.communication.transport.Transport
import com.example.flashfloodcommunication.communication.transport.TransportListener
import java.util.Collections
import java.util.UUID

class BleTransport(
    private val context: Context
) : Transport {

    companion object {
        private const val TAG = "BleTransport"
        private const val BLE_MESH_TAG = "BLE_MESH"
        val MESH_SERVICE_UUID: UUID = UUID.fromString("0000A1E0-0000-1000-8000-00805F9B34FB")

        // 3.5 seconds burst is optimal: catches peer scanners without causing RF collisions
        private const val ADVERTISE_DURATION_MS = 3500L

        // GLOBAL thread-safe cache across the whole app lifecycle
        // Prevents loopbacks, echoes, and repeated rings on sender or receivers
        val seenAlertIds: MutableSet<String> = Collections.synchronizedSet(LinkedHashSet<String>())
        private const val MAX_SEEN_ALERTS = 256
        private const val MAX_HOPS = 3
    }

    private var listener: TransportListener? = null
    private var isRunning = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var stopAdvertiseRunnable: Runnable? = null
    private var isAdvertising = false
    private val advertiseLock = Any()

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothManager?.adapter
    }

    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleScanner: BluetoothLeScanner? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            synchronized(advertiseLock) {
                isAdvertising = true
            }
            Log.d(TAG, "BLE Mesh Advertising Broadcast Active!")
        }

        override fun onStartFailure(errorCode: Int) {
            synchronized(advertiseLock) {
                isAdvertising = false
            }
            val errorMessage = when (errorCode) {
                ADVERTISE_FAILED_ALREADY_STARTED -> "ADVERTISE_FAILED_ALREADY_STARTED"
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "ADVERTISE_FAILED_DATA_TOO_LARGE"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "ADVERTISE_FAILED_FEATURE_UNSUPPORTED"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "ADVERTISE_FAILED_INTERNAL_ERROR"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "ADVERTISE_FAILED_TOO_MANY_ADVERTISERS"
                else -> "Unknown error code: $errorCode"
            }
            Log.e(TAG, "BLE Advertising Failed: $errorMessage")
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            result?.let { handleScanResult(it) }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            super.onBatchScanResults(results)
            results?.forEach { handleScanResult(it) }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE Scan Failed with error code: $errorCode")
        }
    }

    override fun start() {
        if (!isAvailable()) {
            Log.e(TAG, "BLE not supported or Bluetooth disabled.")
            return
        }

        if (!hasPermissions()) {
            Log.e(TAG, "Missing Bluetooth permissions! Start aborted.")
            return
        }

        isRunning = true
        bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        bleScanner = bluetoothAdapter?.bluetoothLeScanner

        startScanning()
        Log.d(TAG, "BleTransport initialized and listening.")
    }

    override fun stop() {
        if (!isRunning) return
        isRunning = false
        stopAdvertising()
        stopScanning()
        Log.d(TAG, "BleTransport stopped.")
    }

    override fun isAvailable(): Boolean {
        val hasFeature = context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        val isEnabled = bluetoothAdapter?.isEnabled == true
        return hasFeature && isEnabled
    }

    @SuppressLint("MissingPermission")
    override fun send(alert: AlertPacket, peerId: String) {
        if (!isRunning || !hasPermissions()) {
            Log.w(TAG, "Cannot broadcast: Transport inactive or permissions missing.")
            return
        }

        // Claim both the app-level id and the on-wire canonical id so Device B
        // echoes (decoded as ALERT_<hash>) cannot re-enter this node.
        rememberAlertId(alert.alertId)
        rememberAlertId(AlertCodec.canonicalAlertId(alert.alertId))

        startAdvertisingPayload(alert)
    }

    override fun setListener(listener: TransportListener) {
        this.listener = listener
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertisingPayload(alert: AlertPacket) {
        if (bleAdvertiser == null) {
            bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        }

        if (bleAdvertiser == null) {
            Log.e(TAG, "BLE Advertiser unavailable on this device.")
            return
        }

        // Stop any existing advertising first to prevent ADVERTISE_FAILED_ALREADY_STARTED
        stopAdvertising()

        // Wait a brief moment to ensure the advertiser is fully stopped before restarting
        mainHandler.postDelayed({
            synchronized(advertiseLock) {
                if (isAdvertising) {
                    Log.w(TAG, "Advertiser still active, attempting to stop again")
                    stopAdvertising()
                }
            }

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(false)
                .setTimeout(0)
                .build()

            val payloadData = AlertCodec.encode(alert)
            val meshUuid = ParcelUuid(MESH_SERVICE_UUID)

            // Keep the 16-byte payload in the primary advertisement only (31-byte limit).
            // Device B matches via ScanFilter.setServiceData, not the UUID list.
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceData(meshUuid, payloadData)
                .build()

            val scanResponse = AdvertiseData.Builder()
                .addServiceUuid(meshUuid)
                .build()

            try {
                bleAdvertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
                Log.d(TAG, "Broadcasting BLE Mesh Packet: ${alert.alertId}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start BLE advertising: ${e.message}")
                synchronized(advertiseLock) {
                    isAdvertising = false
                }
            }

            // Automatically turn off antenna after burst to prevent jamming the channel
            stopAdvertiseRunnable?.let { mainHandler.removeCallbacks(it) }
            stopAdvertiseRunnable = Runnable {
                stopAdvertising()
            }
            mainHandler.postDelayed(stopAdvertiseRunnable!!, ADVERTISE_DURATION_MS)
        }, 100L) // 100ms delay to ensure clean stop/start cycle
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertising() {
        stopAdvertiseRunnable?.let {
            mainHandler.removeCallbacks(it)
            stopAdvertiseRunnable = null
        }

        if (hasPermissions() && bluetoothAdapter?.isEnabled == true) {
            try {
                bleAdvertiser?.stopAdvertising(advertiseCallback)
                synchronized(advertiseLock) {
                    isAdvertising = false
                }
                Log.d(TAG, "BLE Advertising stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping BLE advertiser: ${e.message}")
                synchronized(advertiseLock) {
                    isAdvertising = false
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startScanning() {
        if (!hasPermissions() || bluetoothAdapter?.isEnabled != true) return

        if (bleScanner == null) {
            bleScanner = bluetoothAdapter?.bluetoothLeScanner
        }

        val filter = ScanFilter.Builder()
            .setServiceData(ParcelUuid(MESH_SERVICE_UUID), ByteArray(0))
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        try {
            bleScanner?.startScan(listOf(filter), settings, scanCallback)
            Log.d(TAG, "BLE Scanner listening for mesh packets...")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start scan: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopScanning() {
        if (hasPermissions() && bluetoothAdapter?.isEnabled == true) {
            try {
                bleScanner?.stopScan(scanCallback)
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping scan: ${e.message}")
            }
        }
    }

    private fun handleScanResult(result: ScanResult) {
        val record = result.scanRecord ?: return
        val serviceData = record.getServiceData(ParcelUuid(MESH_SERVICE_UUID)) ?: return

        Log.d(BLE_MESH_TAG, "BLE scan result received with service data: ${serviceData.size} bytes")

        val receivedPacket = AlertCodec.decode(serviceData)
        if (receivedPacket == null) {
            Log.e(BLE_MESH_TAG, "Failed to decode BLE packet from service data")
            return
        }

        Log.d(BLE_MESH_TAG, "Successfully decoded BLE packet: alertId=${receivedPacket.alertId}, eventType=${receivedPacket.eventType}")

        val canonicalId = AlertCodec.canonicalAlertId(receivedPacket.alertId)

        // HARD DEDUPLICATION: drop own echoes and BLE advertising bursts
        if (hasSeenAlert(receivedPacket.alertId) || hasSeenAlert(canonicalId)) {
            Log.d(BLE_MESH_TAG, "Duplicate alert detected, dropping: ${receivedPacket.alertId}")
            return
        }

        rememberAlertId(receivedPacket.alertId)
        rememberAlertId(canonicalId)
        Log.d(BLE_MESH_TAG, "New alert remembered in dedup cache: ${receivedPacket.alertId}")

        if (receivedPacket.hopCount >= MAX_HOPS) {
            Log.d(BLE_MESH_TAG, "Max hops exceeded for ${receivedPacket.alertId}. Delivering locally without further scan fan-out.")
        }

        val senderAddress = result.device.address ?: "BLE_PEER"
        Log.d(BLE_MESH_TAG, "Received new mesh alert from $senderAddress: ${receivedPacket.alertId}, hopCount=${receivedPacket.hopCount}, ttl=${receivedPacket.ttl}")

        // Do not call onPeerDiscovered here: that dumps the entire DTN store back
        // on the air for every unique packet and causes A↔B advertise loops.
        Log.d(BLE_MESH_TAG, "Forwarding packet to CommunicationManager for database insertion")
        listener?.onPacketReceived(packet = receivedPacket, senderId = senderAddress)
    }

    private fun hasSeenAlert(alertId: String): Boolean {
        return seenAlertIds.contains(alertId)
    }

    private fun rememberAlertId(alertId: String) {
        synchronized(seenAlertIds) {
            seenAlertIds.add(alertId)
            while (seenAlertIds.size > MAX_SEEN_ALERTS) {
                val iterator = seenAlertIds.iterator()
                if (!iterator.hasNext()) break
                iterator.next()
                iterator.remove()
            }
        }
    }

    private fun hasPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }
}
