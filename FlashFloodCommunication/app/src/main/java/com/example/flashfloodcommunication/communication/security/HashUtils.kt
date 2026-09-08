package com.example.flashfloodcommunication.communication.security

import com.example.flashfloodcommunication.communication.core.AlertPacket
import java.security.MessageDigest

object HashUtils {
    fun calculatePayloadHash(alert: AlertPacket): String {
        val rawData = "${alert.alertId}:${alert.eventType}:${alert.severity}:${alert.riskScore}:${alert.issuedAt}:${alert.expiresAt}:${alert.latitude}:${alert.longitude}:${alert.instructionEn}:${alert.priority}:${alert.ttl}"
        val bytes = MessageDigest.getInstance("SHA-256").digest(rawData.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
