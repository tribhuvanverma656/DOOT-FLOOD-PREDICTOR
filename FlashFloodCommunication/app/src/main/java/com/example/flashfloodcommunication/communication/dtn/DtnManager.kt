package com.example.flashfloodcommunication.communication.dtn

import android.content.Context
import android.util.Log
import com.example.flashfloodcommunication.communication.core.AlertPacket
import com.example.flashfloodcommunication.communication.security.SignatureVerifier
import com.example.flashfloodcommunication.communication.notification.AlertNotifier
import java.util.Collections

class DtnManager(
    private val context: Context,
    private val dtnStore: DtnStore,
    private val signatureVerifier: SignatureVerifier
) {

    companion object {
        private const val TAG = "DtnManager"
        private const val BLE_MESH_TAG = "BLE_MESH"
        // Synchronized set to prevent processing duplicate BLE advertising burst frames
        private val seenAlertIds = Collections.synchronizedSet(LinkedHashSet<String>())
    }

    /**
     * Processes an incoming alert from a peer:
     * 1. Checks in-memory deduplication cache
     * 2. Validates TTL and expiration
     * 3. Checks signature authenticity
     * 4. Persists to Room DTN store
     * 5. Triggers audible emergency alert notification
     * 6. Returns a prepared relay packet if eligible for rebroadcast, or null if dropped
     */
    suspend fun processIncomingAlert(alert: AlertPacket, senderId: String): AlertPacket? {
        val currentTime = System.currentTimeMillis()

        Log.d(BLE_MESH_TAG, "Processing alert: alertId=${alert.alertId}, senderId=$senderId, ttl=${alert.ttl}, hopCount=${alert.hopCount}")

        // 1. Fast-path in-memory deduplication
        if (seenAlertIds.contains(alert.alertId)) {
            Log.d(BLE_MESH_TAG, "Duplicate BLE burst packet ignored: ${alert.alertId}")
            return null
        }

        // 2. Guard against expired packets or zero TTL
        if (alert.ttl <= 0) {
            Log.d(BLE_MESH_TAG, "Dropped alert ${alert.alertId}: TTL exhausted (${alert.ttl})")
            return null
        }

        if (alert.expiresAt <= currentTime) {
            Log.d(BLE_MESH_TAG, "Dropped alert ${alert.alertId}: Alert expired at ${alert.expiresAt}")
            return null
        }

        // 3. Cryptographic signature check
        if (!signatureVerifier.verify(alert)) {
            Log.w(BLE_MESH_TAG, "Dropped alert ${alert.alertId}: Invalid signature from $senderId")
            return null
        }

        Log.d(BLE_MESH_TAG, "Alert ${alert.alertId} passed validation, attempting database insertion")

        // 4. Save locally in Room (returns false if duplicate or already stored)
        val isNewAlert = dtnStore.saveAlert(alert, senderId)
        if (!isNewAlert) {
            seenAlertIds.add(alert.alertId)
            Log.d(BLE_MESH_TAG, "Alert ${alert.alertId} is already in local DTN store. Skipping relay.")
            return null
        }

        // Mark as seen in cache
        seenAlertIds.add(alert.alertId)
        Log.d(BLE_MESH_TAG, "Successfully stored fresh alert ${alert.alertId} locally from $senderId in database")

        // 5. Fire audible alarm and notification banner
        try {
            Log.d(BLE_MESH_TAG, "Firing emergency notification for alert ${alert.alertId}")
            AlertNotifier.showEmergencyNotification(
                context = context,
                title = "FLASH FLOOD WARNING",
                message = alert.instructionEn ?: "Evacuate immediately to high ground!"
            )
        } catch (e: Exception) {
            Log.e(BLE_MESH_TAG, "Failed to fire emergency notification: ${e.message}")
        }

        // Relay for mesh peers (Device B). Skip only when hops/TTL are exhausted.
        // originatorId on decoded BLE packets is BLE_MESH; LOCAL_NODE is in-memory only
        // and must not block Device B from forwarding a received flood warning.
        return if (alert.ttl > 1 && alert.hopCount + 1 < 3 && senderId != "LOCAL_SENDER") {
            Log.d(BLE_MESH_TAG, "Alert ${alert.alertId} eligible for relay: ttl=${alert.ttl}, hopCount=${alert.hopCount}")
            alert.copy(
                ttl = alert.ttl - 1,
                hopCount = alert.hopCount + 1
            )
        } else {
            Log.d(BLE_MESH_TAG, "Alert ${alert.alertId} stored locally without relay (ttl=${alert.ttl}, hopCount=${alert.hopCount})")
            null
        }
    }

    /**
     * Collects all currently stored active alerts from the database that can still be forwarded.
     */
    suspend fun prepareAlertsForForwarding(): List<AlertPacket> {
        val currentTime = System.currentTimeMillis()
        return dtnStore.getActiveAlerts()
            .filter { it.expiresAt > currentTime && it.ttl > 1 }
            .map { alert ->
                alert.copy(
                    ttl = alert.ttl - 1,
                    hopCount = alert.hopCount + 1
                )
            }
    }
}
