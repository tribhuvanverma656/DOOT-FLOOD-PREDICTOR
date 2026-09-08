package com.example.flashfloodcommunication.communication.core

import android.util.Log
import com.example.flashfloodcommunication.communication.dtn.DtnManager
import com.example.flashfloodcommunication.communication.transport.Transport
import com.example.flashfloodcommunication.communication.transport.TransportListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class CommunicationManager(
    private val dtnManager: DtnManager,
    private val transport: Transport,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) : TransportListener {

    companion object {
        private const val TAG = "CommunicationManager"
        private const val BLE_MESH_TAG = "BLE_MESH"
    }

    fun startCommunication() {
        transport.setListener(this)
        transport.start()
    }

    fun stopCommunication() {
        transport.stop()
    }

    suspend fun broadcastAlert(alert: AlertPacket): Boolean {
        transport.send(alert, "BROADCAST")
        return true
    }

    override fun onPacketReceived(packet: AlertPacket, senderId: String) {
        Log.d(BLE_MESH_TAG, "CommunicationManager received packet: alertId=${packet.alertId}, senderId=$senderId")
        scope.launch(Dispatchers.IO) {
            Log.d(BLE_MESH_TAG, "Processing incoming alert in DtnManager: ${packet.alertId}")
            val packetToRelay = dtnManager.processIncomingAlert(packet, senderId)

            if (packetToRelay != null) {
                Log.d(BLE_MESH_TAG, "Alert ${packet.alertId} is fresh and eligible for relay. Adding jitter before rebroadcast.")
                // Random jitter (300ms - 1500ms) to prevent RF collision if multiple peers forward at once
                val jitterMs = (300L..1500L).random()
                kotlinx.coroutines.delay(jitterMs)

                transport.send(packetToRelay, "BROADCAST")
                Log.d(BLE_MESH_TAG, "Alert ${packet.alertId} rebroadcasted with jitter: ${jitterMs}ms")
            } else {
                Log.d(BLE_MESH_TAG, "Alert ${packet.alertId} was not relayed (either duplicate, expired, or TTL exhausted)")
            }
        }
    }

    override fun onPeerDiscovered(peerId: String) {
        // BLE mesh is already a broadcast advertisement. Replaying the DTN store
        // on every discovered address re-queues the same alert and loops Device A/B.
    }

    override fun onPeerLost(peerId: String) {
        // Handle disconnects
    }
}
