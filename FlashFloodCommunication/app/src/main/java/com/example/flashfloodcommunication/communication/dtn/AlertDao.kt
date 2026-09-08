package com.example.flashfloodcommunication.communication.dtn

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface AlertDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAlert(alert: AlertEntity)

    @Query("SELECT * FROM alerts WHERE alertId = :alertId LIMIT 1")
    suspend fun getAlertById(alertId: String): AlertEntity?

    @Query("DELETE FROM alerts")
    suspend fun clearAllAlerts(): Int

    @Query("SELECT * FROM alerts WHERE expiresAt > :currentTime ORDER BY priority DESC")
    suspend fun getValidAlerts(currentTime: Long): List<AlertEntity>

    @Query("DELETE FROM alerts WHERE expiresAt <= :currentTime")
    suspend fun deleteExpiredAlerts(currentTime: Long): Int

    // Added for Option A: Returns a real-time reactive stream of all alerts
    @Query("SELECT * FROM alerts ORDER BY issuedAt DESC")
    fun getAllAlerts(): Flow<List<AlertEntity>>
}
