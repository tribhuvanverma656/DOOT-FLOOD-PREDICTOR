package com.example.flashfloodcommunication.communication.dtn

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "alerts")
data class AlertEntity(
    @PrimaryKey
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
    val receivedAt: Long = System.currentTimeMillis()
)
