package com.example.flashfloodcommunication

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
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
import com.example.flashfloodcommunication.ui.theme.FlashFloodCommunicationTheme
import com.example.flashfloodcommunication.workers.LocationSyncWorker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity() {

    private var commManager: CommunicationManager? = null
    private var dtnManagerInstance: DtnManager? = null
    private var isBleInitialized by mutableStateOf(false)

    private val alertViewModel: AlertViewModel by viewModels {
        val database = DtnDatabase.getDatabase(applicationContext)
        val repository = AlertRepository(database.alertDao())
        AlertViewModelFactory(repository)
    }

    private val enableBtLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            setupCommunicationManager()
        } else {
            Toast.makeText(this, "Bluetooth must be enabled for mesh alerts", Toast.LENGTH_SHORT).show()
        }
    }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val fineLocationGranted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] ?: (
                ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                )

        if (fineLocationGranted) {
            scheduleLocationSyncWorkers()
        } else {
            Toast.makeText(this, "Location permission required for flood geofencing.", Toast.LENGTH_SHORT).show()
        }

        checkBluetoothAndStart()
    }

    @SuppressLint("MissingPermission")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        checkAndRequestPermissions()

        setContent {
            FlashFloodCommunicationTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    MainAlertScreen(
                        statusText = if (isBleInitialized) "Mesh Active" else "Initializing...",
                        viewModel = alertViewModel,
                        onSendAlertClick = {
                            if (commManager == null || !isBleInitialized) {
                                Toast.makeText(this@MainActivity, "Mesh initializing...", Toast.LENGTH_SHORT).show()
                                return@MainAlertScreen
                            }

                            // PROPER FIX: Explicitly check permission before accessing location
                            if (ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                                Toast.makeText(this@MainActivity, "Location permission required to send alerts", Toast.LENGTH_SHORT).show()
                                return@MainAlertScreen
                            }

                            val fusedClient = com.google.android.gms.location.LocationServices.getFusedLocationProviderClient(this@MainActivity)
                            fusedClient.lastLocation.addOnSuccessListener { location ->
                                // ... (Keep the rest of your Supabase / Offline Fallback logic exactly the same)
                                val currentLat = location?.latitude ?: 28.6794929
                                val currentLon = location?.longitude ?: 77.5002084

                                lifecycleScope.launch(Dispatchers.IO) {
                                    try {
                                        val client = okhttp3.OkHttpClient()
                                        val mediaType = "application/json; charset=utf-8".toMediaType()
                                        val rpcPayload = JSONObject().apply {
                                            put("user_lat", currentLat)
                                            put("user_lon", currentLon)
                                        }

                                        val request = okhttp3.Request.Builder()
                                            .url("https://fobsqygqbjywhijqzxhh.supabase.co/rest/v1/rpc/check_danger_geofence")
                                            .addHeader("apikey", "sb_publishable_lY0LO2eRn62MB3biYi7Jiw_w5H1hNP_")
                                            .addHeader("Authorization", "Bearer sb_publishable_lY0LO2eRn62MB3biYi7Jiw_w5H1hNP_")
                                            .addHeader("Content-Type", "application/json")
                                            .post(rpcPayload.toString().toRequestBody(mediaType))
                                            .build()

                                        val response = client.newCall(request).execute()
                                        val body = response.body?.string()

                                        if (response.isSuccessful && !body.isNullOrEmpty()) {
                                            val jsonArray = JSONArray(body)
                                            if (jsonArray.length() > 0) {
                                                val item = jsonArray.getJSONObject(0)

                                                // Fresh UUID every tap so Room INSERTs a new row, the UI count
                                                // increments, and BleTransport does not drop Phone A's next broadcast.
                                                val safeAlertId = UUID.randomUUID().toString()

                                                val alertEntity = AlertEntity(
                                                    alertId = safeAlertId,
                                                    eventType = item.getString("zone_name"),
                                                    severity = 0,
                                                    riskScore = item.getDouble("risk_score"),
                                                    issuedAt = System.currentTimeMillis(),
                                                    expiresAt = System.currentTimeMillis() + 3600000L,
                                                    latitude = currentLat,
                                                    longitude = currentLon,
                                                    instructionEn = item.getString("instruction_en"),
                                                    instructionHi = item.getString("instruction_hi"),
                                                    priority = 10,
                                                    ttl = 5,
                                                    hopCount = 0,
                                                    copyCount = 1,
                                                    payloadHash = "GEO_HASH",
                                                    signature = "SIG_SUPABASE"
                                                )

                                                transmitMeshAlert(
                                                    alertEntity = alertEntity,
                                                    originatorId = "SUPABASE_GATEWAY",
                                                    toastMessage = "Alert pulled dynamically!"
                                                )
                                            } else {
                                                withContext(Dispatchers.Main) {
                                                    Toast.makeText(this@MainActivity, "No active hazard at your coordinates", Toast.LENGTH_SHORT).show()
                                                }
                                            }
                                        } else {
                                            transmitOfflineFallbackAlert(
                                                lat = currentLat,
                                                lon = currentLon,
                                                reason = "Server unreachable (${response.code})"
                                            )
                                        }
                                    } catch (e: Exception) {
                                        transmitOfflineFallbackAlert(
                                            lat = currentLat,
                                            lon = currentLon,
                                            reason = e.message ?: "network error"
                                        )
                                    }
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private fun scheduleLocationSyncWorkers() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val locationSyncRequest = PeriodicWorkRequestBuilder<LocationSyncWorker>(30, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            "LocationSyncWork",
            ExistingPeriodicWorkPolicy.UPDATE,
            locationSyncRequest
        )

        val immediateSync = OneTimeWorkRequestBuilder<LocationSyncWorker>()
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            "LocationSyncImmediate",
            ExistingWorkPolicy.REPLACE,
            immediateSync
        )
    }

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
            requestPermissionLauncher.launch(permissionsToRequest.toTypedArray())
        } else {
            scheduleLocationSyncWorkers()
            checkBluetoothAndStart()
        }
    }

    private fun checkBluetoothAndStart() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = bluetoothManager?.adapter

        if (adapter != null && !adapter.isEnabled) {
            val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            enableBtLauncher.launch(enableBtIntent)
        } else {
            setupCommunicationManager()
        }
    }

    private fun setupCommunicationManager() {
        if (isBleInitialized) return

        lifecycleScope.launch(Dispatchers.IO) {
            val database = DtnDatabase.getDatabase(applicationContext)
            val dao = database.alertDao()
            val dtnStore = DtnStore(dao)
            val signatureVerifier = AcceptAllSignatureVerifier()
            val dtnManager = DtnManager(applicationContext, dtnStore, signatureVerifier)

            dtnManagerInstance = dtnManager
            val bleTransport = BleTransport(applicationContext)

            commManager = CommunicationManager(dtnManager, bleTransport)
            commManager?.startCommunication()

            withContext(Dispatchers.Main) {
                isBleInitialized = true
            }
        }
    }

    /**
     * Device B (or any node) with no cloud: still emit one BLE mesh packet.
     * Dedup in BleTransport prevents that packet from echoing back as a new alert.
     */
    private suspend fun transmitOfflineFallbackAlert(lat: Double, lon: Double, reason: String) {
        val now = System.currentTimeMillis()
        val alertEntity = AlertEntity(
            alertId = UUID.randomUUID().toString(),
            eventType = "FLASH_FLOOD",
            severity = Severity.CRITICAL.ordinal,
            riskScore = 90.0,
            issuedAt = now,
            expiresAt = now + 3600000L,
            latitude = lat,
            longitude = lon,
            instructionEn = "Evacuate immediately to higher ground!",
            instructionHi = "Turant unchi jagah par jayein!",
            priority = 10,
            ttl = 5,
            hopCount = 0,
            copyCount = 1,
            payloadHash = "GEO_HASH",
            signature = "SIG_OFFLINE"
        )
        transmitMeshAlert(
            alertEntity = alertEntity,
            originatorId = "LOCAL_NODE",
            toastMessage = "Offline mesh alert sent ($reason)"
        )
    }

    private suspend fun transmitMeshAlert(
        alertEntity: AlertEntity,
        originatorId: String,
        toastMessage: String
    ) {
        alertViewModel.insertAlert(alertEntity)

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
            originatorId = originatorId
        )

        commManager?.broadcastAlert(packet)

        withContext(Dispatchers.Main) {
            AlertNotifier.showEmergencyNotification(
                context = applicationContext,
                title = "FLASH FLOOD DETECTED",
                message = alertEntity.instructionEn ?: "Evacuate immediately!"
            )
            Toast.makeText(this@MainActivity, toastMessage, Toast.LENGTH_SHORT).show()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        commManager?.stopCommunication()
    }
}

fun getSeverityColor(severity: Int): Color {
    return when (severity) {
        Severity.CRITICAL.ordinal -> Color(0xFFD32F2F)
        Severity.HIGH.ordinal -> Color(0xFFF57C00)
        Severity.MEDIUM.ordinal -> Color(0xFFFBC02D)
        else -> Color(0xFF1976D2)
    }
}

fun formatTimestamp(timestamp: Long): String {
    val sdf = SimpleDateFormat("dd MMM, hh:mm a", Locale.getDefault())
    return sdf.format(Date(timestamp))
}

@Composable
fun MainAlertScreen(
    statusText: String,
    viewModel: AlertViewModel,
    onSendAlertClick: () -> Unit
) {
    // collectAsState automatically collects on the main thread in Compose
    // This ensures immediate UI updates when the database emits new data
    val alertList by viewModel.alertList.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Flash Flood Offline Mesh",
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(text = "Status: $statusText")

        Spacer(modifier = Modifier.height(16.dp))

        Button(onClick = onSendAlertClick) {
            Text("Send Test Emergency Alert")
        }

        Button(
            onClick = { AlertNotifier.stopEmergencyAlarm() },
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
                contentColor = MaterialTheme.colorScheme.onErrorContainer
            ),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp)
        ) {
            Text(text = "Silence Alarm / Mute", fontWeight = FontWeight.Bold)
        }

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Stored Alerts (${alertList.size}):",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.align(Alignment.Start)
        )

        Spacer(modifier = Modifier.height(8.dp))

        LazyColumn(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(alertList) { alert ->
                AlertItemCard(alert = alert)
            }
        }
    }
}

@Composable
fun AlertItemCard(alert: AlertEntity) {
    val badgeColor = getSeverityColor(alert.severity)

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = alert.eventType,
                    style = MaterialTheme.typography.titleMedium
                )
                Surface(
                    color = badgeColor,
                    shape = MaterialTheme.shapes.small
                ) {
                    Text(
                        text = "Priority: ${alert.priority}",
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "ID: ${alert.alertId.take(8)}...",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = alert.instructionEn ?: "No English instruction provided",
                style = MaterialTheme.typography.bodyMedium
            )
            if (!alert.instructionHi.isNullOrEmpty()) {
                Text(
                    text = alert.instructionHi,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            Spacer(modifier = Modifier.height(6.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Risk: ${alert.riskScore}%",
                    style = MaterialTheme.typography.labelSmall
                )
                Text(
                    text = "Issued: ${formatTimestamp(alert.issuedAt)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}