import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'alert_packet.dart';
import 'alert_codec.dart';
import 'ble_transport.dart';

class CommunicationManager {
  static final CommunicationManager _instance = CommunicationManager._internal();
  factory CommunicationManager() => _instance;
  CommunicationManager._internal() {
    _bleTransport.onPacketReceived.listen(receivePacket);
  }

  final BleTransport _bleTransport = BleTransport();
  BleTransport get bleTransport => _bleTransport;

  final List<AlertPacket> _storedPackets = [];
  final Set<String> _seenAlertIds = {};
  final StreamController<AlertPacket> _incomingAlertsController = StreamController<AlertPacket>.broadcast();
  final StreamController<List<AlertPacket>> _alertsListController = StreamController<List<AlertPacket>>.broadcast();

  Stream<AlertPacket> get onAlertReceived => _incomingAlertsController.stream;
  Stream<List<AlertPacket>> get onAlertsChanged => _alertsListController.stream;

  List<AlertPacket> get storedPackets => List.unmodifiable(_storedPackets);

  bool _isMeshActive = true;
  bool get isMeshActive => _isMeshActive;

  void startMesh() {
    _isMeshActive = true;
    _bleTransport.start();
    debugPrint("[CommunicationManager] BLE/LoRA DTN Mesh Controller Active");
  }

  void stopMesh() {
    _isMeshActive = false;
    _bleTransport.stop();
    debugPrint("[CommunicationManager] BLE/LoRA DTN Mesh Controller Stopped");
  }

  /// Broadcast distress alert over local mesh controller immediately (offline first).
  Future<AlertPacket> broadcastDistress({
    required LatLng position,
    required String phone,
    String message = "Emergency SOS Alert Broadcasted via Mesh",
    double riskScore = 95.0,
    int severity = 10,
  }) async {
    final alertId = "SOS_${DateTime.now().millisecondsSinceEpoch}";
    final packet = AlertPacket(
      alertId: alertId,
      eventType: "EMERGENCY_SOS",
      severity: severity,
      riskScore: riskScore,
      issuedAt: DateTime.now().millisecondsSinceEpoch,
      expiresAt: DateTime.now().millisecondsSinceEpoch + (4 * 3600000),
      latitude: position.latitude,
      longitude: position.longitude,
      instructionEn: "SOS Distress Alert: Rescue Needed!",
      instructionHi: "Aapaatkaal: Madad ki zaroorat hai!",
      priority: 10,
      ttl: 5,
      hopCount: 0,
      originatorId: "LOCAL_DEVICE",
      senderPhone: phone,
      message: message,
    );

    // Verify wire encoding
    final encoded = AlertCodec.encode(packet);
    debugPrint("[CommunicationManager] Alert encoded: ${encoded.length} bytes for wire broadcast");

    // Add to local DTN store and dedup cache
    _seenAlertIds.add(alertId);
    _seenAlertIds.add(AlertCodec.canonicalAlertId(alertId));
    _storedPackets.insert(0, packet);

    // Notify realtime listeners
    _incomingAlertsController.add(packet);
    _alertsListController.add(List.unmodifiable(_storedPackets));

    // Wire broadcast across BLE nodes
    await _bleTransport.send(packet);

    debugPrint("[CommunicationManager] Broadcasted SOS packet: $alertId over offline mesh.");
    return packet;
  }

  /// Broadcast emergency siren trigger packet over offline mesh to propagate to other devices.
  Future<AlertPacket> broadcastSirenTrigger({
    required LatLng position,
    String message = "EMERGENCY FLOOD SIREN: Multi-Device Siren Propagation Active",
    double riskScore = 95.0,
  }) async {
    final alertId = "SIREN_${DateTime.now().millisecondsSinceEpoch}";
    final packet = AlertPacket(
      alertId: alertId,
      eventType: "SIREN_TRIGGER",
      severity: 10,
      riskScore: riskScore,
      issuedAt: DateTime.now().millisecondsSinceEpoch,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 1800000,
      latitude: position.latitude,
      longitude: position.longitude,
      instructionEn: "EMERGENCY SIREN PROPAGATION: Multi-Device Alert Active!",
      instructionHi: "Aapaatkaal: Sabhi phone par siren baj raha hai!",
      priority: 10,
      ttl: 5,
      hopCount: 0,
      originatorId: "LOCAL_DEVICE",
      senderPhone: "MESH_SIREN_NODE",
      message: message,
    );

    final encoded = AlertCodec.encode(packet);
    debugPrint("[CommunicationManager] Siren packet encoded: ${encoded.length} bytes for wire broadcast");

    _seenAlertIds.add(alertId);
    _seenAlertIds.add(AlertCodec.canonicalAlertId(alertId));
    _storedPackets.insert(0, packet);

    _incomingAlertsController.add(packet);
    _alertsListController.add(List.unmodifiable(_storedPackets));

    // Wire broadcast across BLE nodes
    await _bleTransport.send(packet);

    debugPrint("[CommunicationManager] Broadcasted siren trigger: $alertId over offline mesh.");
    return packet;
  }

  /// Ingest an incoming packet from BLE advertisement or peer relay
  void receivePacket(AlertPacket packet) {
    final canonicalId = AlertCodec.canonicalAlertId(packet.alertId);
    if (_seenAlertIds.contains(packet.alertId) || _seenAlertIds.contains(canonicalId)) {
      debugPrint("[CommunicationManager] Duplicate packet dropped: ${packet.alertId}");
      return;
    }

    _seenAlertIds.add(packet.alertId);
    _seenAlertIds.add(canonicalId);
    _storedPackets.insert(0, packet);

    _incomingAlertsController.add(packet);
    _alertsListController.add(List.unmodifiable(_storedPackets));
    debugPrint("[CommunicationManager] New mesh packet received and stored: ${packet.alertId}");
  }
}
