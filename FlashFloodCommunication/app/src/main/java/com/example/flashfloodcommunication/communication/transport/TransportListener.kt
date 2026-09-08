package com.example.flashfloodcommunication.communication.transport

import com.example.flashfloodcommunication.communication.core.AlertPacket

interface TransportListener {
    fun onPacketReceived(packet: AlertPacket, senderId: String)
    fun onPeerDiscovered(peerId: String)
    fun onPeerLost(peerId: String)
}
