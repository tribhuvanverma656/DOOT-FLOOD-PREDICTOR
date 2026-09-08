package com.example.flashfloodcommunication.communication.security

import com.example.flashfloodcommunication.communication.core.AlertPacket

class AcceptAllSignatureVerifier : SignatureVerifier {
    override fun verify(alert: AlertPacket): Boolean {
        // Prototype stub: accepts all signed alerts for local testing
        return alert.signature.isNotEmpty()
    }
}
