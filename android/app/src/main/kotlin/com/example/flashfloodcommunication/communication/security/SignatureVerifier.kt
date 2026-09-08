package com.example.flashfloodcommunication.communication.security

import com.example.flashfloodcommunication.communication.core.AlertPacket

interface SignatureVerifier {
    fun verify(alert: AlertPacket): Boolean
}
