package com.example.flashfloodcommunication

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.flashfloodcommunication.communication.core.AlertPacket
import com.example.flashfloodcommunication.communication.core.CommunicationManager
import com.example.flashfloodcommunication.communication.dtn.AlertEntity
import com.example.flashfloodcommunication.communication.dtn.AlertRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class AlertViewModel(private val repository: AlertRepository) : ViewModel() {

    // Converts Flow to StateFlow for optimal Compose rendering
    // Collect on Dispatchers.Main.immediate to ensure immediate UI updates upon database insert
    val alertList: StateFlow<List<AlertEntity>> = repository.allAlerts
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    fun insertAlert(alert: AlertEntity) {
        viewModelScope.launch(Dispatchers.IO) {
            repository.insertAlert(alert)
        }
    }

    fun broadcastAlert(commManager: CommunicationManager?, alert: AlertPacket, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val success = commManager?.broadcastAlert(alert) ?: false
            onResult(success)
        }
    }
    fun clearExpiredAlerts() {
        viewModelScope.launch {
            val currentTime = System.currentTimeMillis()
            val deletedCount = repository.deleteExpiredAlerts(currentTime)
            // Optionally logging ya handling
        }
    }

}

// Factory to pass AlertRepository into AlertViewModel
class AlertViewModelFactory(private val repository: AlertRepository) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(AlertViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return AlertViewModel(repository) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }

}
