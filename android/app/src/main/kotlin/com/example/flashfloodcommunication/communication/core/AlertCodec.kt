package com.example.flashfloodcommunication.communication.core

import java.nio.ByteBuffer
import java.nio.ByteOrder

object AlertCodec {

    // Pre-mapped instruction dictionary available locally offline on all devices
    val PRESET_INSTRUCTIONS = mapOf(
        1 to Pair("Evacuate immediately to higher ground!", "Turant unchi jagah par jayein!"),
        2 to Pair("Flash flood warning! Move away from river banks!", "Baadh ki chetavani! Nadi ke kinare se door rahein!"),
        3 to Pair("Emergency alert: Stay indoors at high altitude.", "Aapaatkaal: Unche sthan par andar hi rahein.")
    )

    /**
     * Stable 32-bit id used on the wire. Decoded packets use "ALERT_" + hex(hash);
     * re-encoding that form must produce the same hash or Device B relays mutate
     * into a new alert and bounce forever.
     */
    fun wireIdHash(alertId: String): Int {
        if (alertId.startsWith("ALERT_")) {
            val hex = alertId.substring(6)
            if (hex.isNotEmpty()) {
                try {
                    return hex.toLong(16).toInt()
                } catch (_: NumberFormatException) {
                    // Fall through to Java hashCode
                }
            }
        }
        return alertId.hashCode()
    }

    fun canonicalAlertId(alertId: String): String {
        return "ALERT_" + Integer.toHexString(wireIdHash(alertId)).uppercase()
    }

    fun encode(alert: AlertPacket): ByteArray {
        val buffer = ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN)

        // 1. Alert ID Hash (4 bytes) — keep stable across hop encode/decode
        buffer.putInt(wireIdHash(alert.alertId))

        // 2. Event Type (high 4 bits) + Severity (low 4 bits) -> 1 byte
        val eventCode = when (alert.eventType) {
            "FLASH_FLOOD" -> 1
            "DAM_BURST" -> 2
            else -> 0
        } and 0x0F
        val sevCode = alert.severity and 0x0F
        buffer.put(((eventCode shl 4) or sevCode).toByte())

        // 3. Risk Score (1 byte: 0-100)
        buffer.put(alert.riskScore.toInt().coerceIn(0, 100).toByte())

        // 4. Latitude (4 bytes: scaled by 1e6)
        buffer.putInt((alert.latitude * 1_000_000).toInt())

        // 5. Longitude (4 bytes: scaled by 1e6)
        buffer.putInt((alert.longitude * 1_000_000).toInt())

        // 6. TTL (high 4 bits) + Hop Count (low 4 bits) -> 1 byte
        val ttlNibble = alert.ttl.coerceIn(0, 15) and 0x0F
        val hopNibble = alert.hopCount.coerceIn(0, 15) and 0x0F
        buffer.put(((ttlNibble shl 4) or hopNibble).toByte())

        // 7. Instruction Codebook ID (1 byte)
        val instructionId = 1.toByte() // Defaults to Preset #1
        buffer.put(instructionId)

        return buffer.array()
    }

    fun decode(bytes: ByteArray): AlertPacket? {
        if (bytes.size < 16) return null

        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)

        // 1. Recover Alert ID
        val idHash = buffer.int
        val alertId = "ALERT_" + Integer.toHexString(idHash).uppercase()

        // 2. Event + Severity
        val eventAndSev = buffer.get().toInt()
        val eventCode = (eventAndSev ushr 4) and 0x0F
        val severity = eventAndSev and 0x0F
        val eventType = when (eventCode) {
            1 -> "FLASH_FLOOD"
            2 -> "DAM_BURST"
            else -> "EMERGENCY"
        }

        // 3. Risk Score
        val riskScore = (buffer.get().toInt() and 0xFF).toDouble()

        // 4. Lat / Lon
        val lat = buffer.int / 1_000_000.0
        val lon = buffer.int / 1_000_000.0

        // 5. TTL + Hop
        val ttlAndHop = buffer.get().toInt()
        val ttl = (ttlAndHop ushr 4) and 0x0F
        // Do not increment here — DtnManager bumps hopCount only when relaying
        val hopCount = ttlAndHop and 0x0F

        // 6. Instruction
        val instructionId = buffer.get().toInt() and 0xFF
        val instructions = PRESET_INSTRUCTIONS[instructionId] ?: Pair("Emergency flood alert!", "Aapaatkaal baadh chetavani!")

        val currentTime = System.currentTimeMillis()

        return AlertPacket(
            alertId = alertId,
            eventType = eventType,
            severity = severity,
            riskScore = riskScore,
            issuedAt = currentTime,
            expiresAt = currentTime + 3600000,
            latitude = lat,
            longitude = lon,
            instructionEn = instructions.first,
            instructionHi = instructions.second,
            priority = 10,
            ttl = ttl,
            hopCount = hopCount,
            copyCount = 1,
            payloadHash = "HASH_${Integer.toHexString(idHash)}",
            signature = "SIG_OFFLINE",
            originatorId = "BLE_MESH"
        )
    }
}