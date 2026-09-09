package com.example.doot

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.flashfloodcommunication.communication.ble.BleTransport
import com.example.flashfloodcommunication.communication.core.AlertPacket
import com.example.flashfloodcommunication.communication.core.CommunicationManager
import com.example.flashfloodcommunication.communication.core.Severity
import com.example.flashfloodcommunication.communication.dtn.AlertEntity
import com.example.flashfloodcommunication.communication.dtn.AlertRepository
import com.example.flashfloodcommunication.communication.dtn.DtnDatabase
import com.example.flashfloodcommunication.communication.dtn.DtnManager
import com.example.flashfloodcommunication.communication.dtn.DtnStore
import com.example.flashfloodcommunication.communication.notification.AlertNotifier
import com.example.flashfloodcommunication.communication.security.AcceptAllSignatureVerifier
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.flashfloodcommunication/ble"

    private var commManager: CommunicationManager? = null
    private var dtnManagerInstance: DtnManager? = null
    private var isBleInitialized = false
    private lateinit var alertRepository: AlertRepository
    private var methodChannel: MethodChannel? = null

    private val activityScope = CoroutineScope(Dispatchers.IO + Job())

    private val REQUEST_PERMISSIONS_CODE = 9001
    private val REQUEST_ENABLE_BT = 9002

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val database = DtnDatabase.getDatabase(applicationContext)
        alertRepository = AlertRepository(database.alertDao())

        checkAndRequestPermissions()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        // Whenever the local alarm sound starts or stops — whether because THIS
        // device pressed a button, or because a BLE packet was received from
        // another device — push the new state to Flutter so the Start/Stop
        // siren buttons on screen stay in sync automatically.
        AlertNotifier.onAlarmStateChanged = { isPlaying ->
            runOnUiThread {
                methodChannel?.invokeMethod("onSirenStateChanged", isPlaying)
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendAlert" -> {
                    sendTestEmergencyAlert()
                    result.success(true)
                }
                "stopAlertSound" -> {
                    stopEmergencyAndBroadcastStop()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun checkAndRequestPermissions() {
        val permissionsToRequest = mutableListOf<String>()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_SCAN)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_ADVERTISE)
            }
        }

        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissionsToRequest.toTypedArray(), REQUEST_PERMISSIONS_CODE)
        } else {
            checkBluetoothAndStart()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_PERMISSIONS_CODE) {
            checkBluetoothAndStart()
        }
    }

    @SuppressLint("MissingPermission")
    private fun checkBluetoothAndStart() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = bluetoothManager?.adapter

        if (adapter != null && !adapter.isEnabled) {
            val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            startActivityForResult(enableBtIntent, REQUEST_ENABLE_BT)
        } else {
            setupCommunicationManager()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ENABLE_BT) {
            if (resultCode == Activity.RESULT_OK) {
                setupCommunicationManager()
            } else {
                Toast.makeText(this, "Bluetooth must be enabled for mesh alerts", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun setupCommunicationManager() {
        if (isBleInitialized) return
        activityScope.launch {
            val database = DtnDatabase.getDatabase(applicationContext)
            val dao = database.alertDao()
            val dtnStore = DtnStore(dao)
            val signatureVerifier = AcceptAllSignatureVerifier()
            val dtnManager = DtnManager(applicationContext, dtnStore, signatureVerifier)

            dtnManagerInstance = dtnManager
            val bleTransport = BleTransport(applicationContext)

            commManager = CommunicationManager(dtnManager, bleTransport)
            commManager?.startCommunication()
            isBleInitialized = true
        }
    }

    // Stops the alarm on THIS device immediately, and also broadcasts a real
    // SIREN_STOP packet over BLE so every other device that heard the siren
    // stops too — instead of silently doing nothing on the mesh like before.
    private fun stopEmergencyAndBroadcastStop() {
        AlertNotifier.stopEmergencyAlarm()

        if (commManager == null || !isBleInitialized) {
            // Mesh not ready yet - local alarm is already stopped, nothing more to do.
            return
        }
        activityScope.launch {
            transmitSirenStop()
        }
    }

    private suspend fun transmitSirenStop() {
        val now = System.currentTimeMillis()
        val stopPacket = AlertPacket(
            alertId = UUID.randomUUID().toString(),
            eventType = "SIREN_STOP",
            severity = Severity.CRITICAL.ordinal,
            riskScore = 0.0,
            issuedAt = now,
            expiresAt = now + 3600000L,
            latitude = 28.6794929,
            longitude = 77.5002084,
            instructionEn = "Siren stopped",
            instructionHi = "Siren band kar di gayi hai",
            priority = 10,
            ttl = 5,
            hopCount = 0,
            copyCount = 1,
            payloadHash = "STOP_HASH",
            signature = "SIG_TEST",
            originatorId = "LOCAL_NODE"
        )
        commManager?.broadcastAlert(stopPacket)
        Log.d("BLE_MESH", "SIREN_STOP broadcasted: ${stopPacket.alertId}")
    }

    private fun sendTestEmergencyAlert() {
        if (commManager == null || !isBleInitialized) {
            Toast.makeText(this, "Mesh initializing... try again in a moment", Toast.LENGTH_SHORT).show()
            return
        }
        activityScope.launch {
            transmitTestAlert()
        }
    }

    private suspend fun transmitTestAlert() {
        val now = System.currentTimeMillis()
        val alertEntity = AlertEntity(
            alertId = UUID.randomUUID().toString(),
            eventType = "FLASH_FLOOD",
            severity = Severity.CRITICAL.ordinal,
            riskScore = 90.0,
            issuedAt = now,
            expiresAt = now + 3600000L,
            latitude = 28.6794929,
            longitude = 77.5002084,
            instructionEn = "Evacuate immediately to higher ground!",
            instructionHi = "Turant unchi jagah par jayein!",
            priority = 10,
            ttl = 5,
            hopCount = 0,
            copyCount = 1,
            payloadHash = "GEO_HASH",
            signature = "SIG_TEST"
        )

        alertRepository.insertAlert(alertEntity)

        val packet = AlertPacket(
            alertId = alertEntity.alertId,
            eventType = "FLASH_FLOOD",
            severity = alertEntity.severity,
            riskScore = alertEntity.riskScore,
            issuedAt = alertEntity.issuedAt,
            expiresAt = alertEntity.expiresAt,
            latitude = alertEntity.latitude,
            longitude = alertEntity.longitude,
            instructionEn = alertEntity.instructionEn,
            instructionHi = alertEntity.instructionHi,
            priority = alertEntity.priority,
            ttl = alertEntity.ttl,
            hopCount = 0,
            copyCount = alertEntity.copyCount,
            payloadHash = alertEntity.payloadHash,
            signature = alertEntity.signature,
            originatorId = "LOCAL_NODE"
        )

        commManager?.broadcastAlert(packet)

        withContext(Dispatchers.Main) {
            AlertNotifier.showEmergencyNotification(
                context = applicationContext,
                title = "FLASH FLOOD DETECTED",
                message = alertEntity.instructionEn ?: "Evacuate immediately!"
            )
            Toast.makeText(this@MainActivity, "Test emergency alert sent", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onDestroy() {
        commManager?.stopCommunication()
        super.onDestroy()
    }
}