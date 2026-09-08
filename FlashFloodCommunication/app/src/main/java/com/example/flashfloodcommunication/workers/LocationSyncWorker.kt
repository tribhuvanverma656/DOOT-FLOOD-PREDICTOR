package com.example.flashfloodcommunication.workers

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.flashfloodcommunication.communication.ble.BleTransport
import com.example.flashfloodcommunication.communication.core.AlertPacket
import com.example.flashfloodcommunication.communication.core.Severity
import com.example.flashfloodcommunication.communication.dtn.DtnDatabase
import com.example.flashfloodcommunication.communication.dtn.DtnManager
import com.example.flashfloodcommunication.communication.dtn.DtnStore
import com.example.flashfloodcommunication.communication.security.AcceptAllSignatureVerifier
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.tasks.await
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class LocationSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        private const val TAG = "LocationSyncWorker"
        private const val SUPABASE_URL = "https://fobsqygqbjywhijqzxhh.supabase.co"
        private const val SUPABASE_KEY = "sb_publishable_lY0LO2eRn62MB3biYi7Jiw_w5H1hNP_"
    }

    @SuppressLint("MissingPermission")
    override suspend fun doWork(): Result {
        val hasFineLocation = ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasFineLocation) {
            Log.e(TAG, "Location permission missing in Worker")
            return Result.failure()
        }

        return try {
            val fusedLocationClient = LocationServices.getFusedLocationProviderClient(applicationContext)
            val cts = CancellationTokenSource()

            val location = fusedLocationClient.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                cts.token
            ).await() ?: fusedLocationClient.lastLocation.await()

            if (location == null) {
                Log.w(TAG, "GPS fix timed out; retrying later")
                return Result.retry()
            }

            val lat = location.latitude
            val lon = location.longitude
            Log.d(TAG, "Acquired GPS fix: Lat=$lat, Lon=$lon (Accuracy: ${location.accuracy}m)")

            // Fetch or generate persistent device UUID
            val sharedPrefs = applicationContext.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
            var deviceId = sharedPrefs.getString("device_id", null)
            if (deviceId == null) {
                deviceId = UUID.randomUUID().toString()
                sharedPrefs.edit().putString("device_id", deviceId).apply()
            }

            val client = OkHttpClient()
            val mediaType = "application/json; charset=utf-8".toMediaType()

            // 1. Update device location in Supabase
            val jsonPayload = JSONObject().apply {
                put("device_id", deviceId)
                put("language", "en")
                put("last_location", "POINT($lon $lat)")
            }

            val syncRequest = Request.Builder()
                .url("$SUPABASE_URL/rest/v1/app_users?on_conflict=device_id")
                .addHeader("apikey", SUPABASE_KEY)
                .addHeader("Authorization", "Bearer $SUPABASE_KEY")
                .addHeader("Content-Type", "application/json")
                .addHeader("Prefer", "resolution=merge-duplicates")
                .post(jsonPayload.toString().toRequestBody(mediaType))
                .build()

            val syncResponse = client.newCall(syncRequest).execute()
            if (!syncResponse.isSuccessful) {
                Log.e(TAG, "Supabase sync error: ${syncResponse.code} - ${syncResponse.body?.string()}")
                return Result.retry()
            }
            Log.d(TAG, "Location successfully synced to Supabase: ($lat, $lon)")

            // 2. Query PostGIS Geofence RPC
            val rpcPayload = JSONObject().apply {
                put("user_lat", lat)
                put("user_lon", lon)
            }

            val rpcRequest = Request.Builder()
                .url("$SUPABASE_URL/rest/v1/rpc/check_danger_geofence")
                .addHeader("apikey", SUPABASE_KEY)
                .addHeader("Authorization", "Bearer $SUPABASE_KEY")
                .addHeader("Content-Type", "application/json")
                .post(rpcPayload.toString().toRequestBody(mediaType))
                .build()

            val rpcResponse = client.newCall(rpcRequest).execute()
            val rpcResponseBody = rpcResponse.body?.string()

            if (rpcResponse.isSuccessful && !rpcResponseBody.isNullOrEmpty()) {
                val jsonArray = JSONArray(rpcResponseBody)

                if (jsonArray.length() > 0) {
                    val zone = jsonArray.getJSONObject(0)
                    val zoneId = zone.getString("zone_id")
                    val zoneName = zone.getString("zone_name")
                    val severityStr = zone.optString("severity", "CRITICAL")
                    val riskScore = zone.optDouble("risk_score", 90.0)
                    val instructionEn = zone.optString("instruction_en", "Evacuate immediately!")
                    val instructionHi = zone.optString("instruction_hi", "Turant unchi jagah par jayein!")

                    Log.w(TAG, "DANGER DETECTED! In zone: $zoneName. Triggering mesh broadcast.")

                    val severityEnum = when (severityStr.uppercase()) {
                        "CRITICAL" -> Severity.CRITICAL
                        "HIGH" -> Severity.HIGH
                        "MODERATE", "MEDIUM" -> Severity.MEDIUM
                        else -> Severity.LOW
                    }

                    val alertPacket = AlertPacket(
                        alertId = zoneId,
                        eventType = "FLASH_FLOOD",
                        severity = severityEnum.ordinal,
                        riskScore = riskScore,
                        issuedAt = System.currentTimeMillis(),
                        expiresAt = System.currentTimeMillis() + 3600000L,
                        latitude = lat,
                        longitude = lon,
                        instructionEn = instructionEn,
                        instructionHi = instructionHi,
                        priority = 10,
                        ttl = 5,
                        hopCount = 0,
                        copyCount = 1,
                        payloadHash = "GEO_HASH",
                        signature = "SIG_OFFLINE",
                        originatorId = "SUPABASE_GATEWAY"
                    )

                    // Save alert to local Room DB and trigger notifications
                    val database = DtnDatabase.getDatabase(applicationContext)
                    val dtnStore = DtnStore(database.alertDao())
                    val dtnManager = DtnManager(applicationContext, dtnStore, AcceptAllSignatureVerifier())
                    dtnManager.processIncomingAlert(alertPacket, "SERVER_INGRESS")

                    // Transmit packet over BLE mesh to warn nearby offline peers
                    val transport = BleTransport(applicationContext)
                    transport.start()
                    transport.send(alertPacket, "BROADCAST")
                } else {
                    Log.d(TAG, "Device coordinate ($lat, $lon) is outside all danger zones.")
                }
            }

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Worker failed with exception: ${e.message}", e)
            Result.retry()
        }
    }
}