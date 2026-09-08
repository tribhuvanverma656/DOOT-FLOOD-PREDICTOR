package com.example.flashfloodcommunication.communication.transport

import com.example.flashfloodcommunication.communication.core.AlertPacket

interface Transport {
    fun start()
    fun stop()
    fun isAvailable(): Boolean
    fun send(alert: AlertPacket, peerId: String)
    fun setListener(listener: TransportListener)
}
