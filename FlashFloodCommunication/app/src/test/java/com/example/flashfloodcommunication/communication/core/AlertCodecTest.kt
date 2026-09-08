package com.example.flashfloodcommunication.communication.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class AlertCodecTest {

    @Test
    fun relayReencodeKeepsStableWireId() {
        val origin = AlertPacket(
            alertId = "zone-uuid-1234",
            eventType = "FLASH_FLOOD",
            severity = 0,
            riskScore = 90.0,
            issuedAt = 1L,
            expiresAt = 2L,
            latitude = 28.6794929,
            longitude = 77.5002084,
            instructionEn = "Evacuate",
            instructionHi = "Turant",
            priority = 10,
            ttl = 5,
            hopCount = 0,
            copyCount = 1,
            payloadHash = "GEO_HASH",
            signature = "SIG_OFFLINE",
            originatorId = "LOCAL_NODE"
        )

        val firstHop = AlertCodec.decode(AlertCodec.encode(origin))
        assertNotNull(firstHop)
        val relayed = firstHop!!.copy(ttl = firstHop.ttl - 1, hopCount = firstHop.hopCount + 1)
        val secondHop = AlertCodec.decode(AlertCodec.encode(relayed))
        assertNotNull(secondHop)

        assertEquals(AlertCodec.canonicalAlertId(origin.alertId), firstHop!!.alertId)
        assertEquals(firstHop!!.alertId, secondHop!!.alertId)
        assertEquals(1, relayed.hopCount)
        assertEquals(1, secondHop!!.hopCount)
    }
}
