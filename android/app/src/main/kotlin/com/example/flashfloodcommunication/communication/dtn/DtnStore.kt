package com.example.flashfloodcommunication.communication.dtn

import android.util.Log
import com.example.flashfloodcommunication.communication.core.AlertPacket

class DtnStore(private val alertDao: AlertDao) {

    companion object {
        private const val TAG = "DtnStore"
        private const val BLE_MESH_TAG = "BLE_MESH"
    }

    suspend fun saveAlert(alert: AlertPacket, receivedFrom: String = "LOCAL"): Boolean {
        Log.d(BLE_MESH_TAG, "DtnStore.saveAlert called for alertId=${alert.alertId}, receivedFrom=$receivedFrom")

        val entity = AlertEntity(
            alertId = alert.alertId,
            eventType = alert.eventType,
            severity = alert.severity,
            riskScore = alert.riskScore,
            issuedAt = alert.issuedAt,
            expiresAt = alert.expiresAt,
            latitude = alert.latitude,
            longitude = alert.longitude,
            instructionEn = alert.instructionEn,
            instructionHi = alert.instructionHi,
            priority = alert.priority,
            ttl = alert.ttl,
            hopCount = alert.hopCount,
            copyCount = alert.copyCount,
            payloadHash = alert.payloadHash,
            signature = alert.signature,
            //receivedFrom = receivedFrom,
            //lastForwardedAt = System.currentTimeMillis()
        )

        // Check if alert already exists - if it does, REPLACE will update it but we return false to prevent relay
        val existingAlert = alertDao.getAlertById(alert.alertId)
        val isNewAlert = existingAlert == null

        if (!isNewAlert) {
            Log.d(BLE_MESH_TAG, "Alert ${alert.alertId} already exists in database (will be updated via REPLACE), returning false to prevent relay")
        } else {
            Log.d(BLE_MESH_TAG, "Alert ${alert.alertId} is new, inserting into database")
        }

        // Use REPLACE strategy to ensure no silent drops - this will update existing alerts or insert new ones
        alertDao.insertAlert(entity)
        Log.d(BLE_MESH_TAG, "Database operation completed for alert ${alert.alertId}, Room should emit update")

        return isNewAlert
    }

    suspend fun getActiveAlerts(): List<AlertPacket> {
        val currentTime = System.currentTimeMillis()
        val entities = alertDao.getValidAlerts(currentTime)
        return entities.map { entity ->
            AlertPacket(
                alertId = entity.alertId,
                eventType = entity.eventType,
                severity = entity.severity,
                riskScore = entity.riskScore,
                issuedAt = entity.issuedAt,
                expiresAt = entity.expiresAt,
                latitude = entity.latitude,
                longitude = entity.longitude,
                instructionEn = entity.instructionEn,
                instructionHi = entity.instructionHi,
                priority = entity.priority,
                ttl = entity.ttl,
                hopCount = entity.hopCount,
                copyCount = entity.copyCount,
                payloadHash = entity.payloadHash,
                signature = entity.signature
            )
        }
    }

    suspend fun cleanupExpiredAlerts(): Int {
        return alertDao.deleteExpiredAlerts(System.currentTimeMillis())
    }
}
