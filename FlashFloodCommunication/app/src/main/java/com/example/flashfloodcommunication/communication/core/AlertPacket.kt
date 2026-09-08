package com.example.flashfloodcommunication.communication.core

data class AlertPacket(
    val alertId: String,
    val eventType: String,
    val severity: Int,
    val riskScore: Double,
    val issuedAt: Long,
    val expiresAt: Long,
    val latitude: Double,
    val longitude: Double,
    val instructionEn: String,
    val instructionHi: String,
    val priority: Int,
    val ttl: Int,
    val hopCount: Int,
    val copyCount: Int,
    val payloadHash: String,
    val signature: String,
    val originatorId: String = "LOCAL_NODE",
)
