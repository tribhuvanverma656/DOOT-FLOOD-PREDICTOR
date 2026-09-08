package com.example.flashfloodcommunication.communication.dtn

import kotlinx.coroutines.flow.Flow

class AlertRepository(private val alertDao: AlertDao) {

    // Expose all alerts as a Flow from DAO
    val allAlerts: Flow<List<AlertEntity>> = alertDao.getAllAlerts()

    suspend fun insertAlert(alert: AlertEntity) {
        alertDao.insertAlert(alert)
    }

    suspend fun deleteExpiredAlerts(currentTime: Long): Int {
        return alertDao.deleteExpiredAlerts(currentTime)
    }
}
