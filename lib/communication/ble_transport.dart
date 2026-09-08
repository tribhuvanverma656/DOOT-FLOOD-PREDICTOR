import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'alert_packet.dart';
import 'alert_codec.dart';

/// Dart BleTransport interacting with native Android BLE advertiser and scanner
/// via the "com.doot.mesh/ble" MethodChannel pipeline.
class BleTransport {
  static final BleTransport _instance = BleTransport._internal();
  factory BleTransport() => _instance;

  static const MethodChannel _channel = MethodChannel('com.doot.mesh/ble');

  final StreamController<AlertPacket> _packetStreamController = StreamController<AlertPacket>.broadcast();
  Stream<AlertPacket> get onPacketReceived => _packetStreamController.stream;

  final Set<String> _seenAlertIds = {};
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  BleTransport._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onPacketReceived') {
      try {
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        final Map<String, dynamic> packetMap = args.map((key, value) => MapEntry(key.toString(), value));
        final packet = AlertPacket.fromJson(packetMap);

        final canonicalId = AlertCodec.canonicalAlertId(packet.alertId);
        if (_seenAlertIds.contains(packet.alertId) || _seenAlertIds.contains(canonicalId)) {
          debugPrint("[BleTransport] Duplicate packet ignored: ${packet.alertId}");
          return;
        }

        rememberAlertId(packet.alertId);
        rememberAlertId(canonicalId);

        debugPrint("[BleTransport] Inbound native BLE alert received: ${packet.alertId}");
        _packetStreamController.add(packet);
      } catch (e) {
        debugPrint("[BleTransport] Error parsing inbound native alert: $e");
      }
    }
  }

  void rememberAlertId(String id) {
    _seenAlertIds.add(id);
    if (_seenAlertIds.length > 256) {
      _seenAlertIds.remove(_seenAlertIds.first);
    }
  }

  bool hasSeenAlert(String id) {
    return _seenAlertIds.contains(id);
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _channel.invokeMethod('startMesh');
      debugPrint("[BleTransport] Native BLE mesh pipeline started.");
    } catch (e) {
      debugPrint("[BleTransport] Notice: Native BLE channel unavailable in current environment: $e");
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    try {
      await _channel.invokeMethod('stopMesh');
      debugPrint("[BleTransport] Native BLE mesh pipeline stopped.");
    } catch (e) {
      debugPrint("[BleTransport] Notice: Native BLE channel stop: $e");
    }
  }

  Future<bool> send(AlertPacket alert) async {
    // 1. Wire validation using AlertCodec
    final wireBytes = AlertCodec.encode(alert);
    debugPrint("[BleTransport] Wire-encoded alert ${alert.alertId} (${wireBytes.length} bytes)");

    // 2. Dedup cache
    rememberAlertId(alert.alertId);
    rememberAlertId(AlertCodec.canonicalAlertId(alert.alertId));

    // 3. Native platform broadcast
    try {
      final success = await _channel.invokeMethod<bool>('sendAlert', {
        'alertId': alert.alertId,
        'eventType': alert.eventType,
        'severity': alert.severity,
        'riskScore': alert.riskScore,
        'latitude': alert.latitude,
        'longitude': alert.longitude,
        'message': alert.message,
        'ttl': alert.ttl,
        'hopCount': alert.hopCount,
      });
      return success ?? true;
    } catch (e) {
      debugPrint("[BleTransport] Notice: Native BLE send fallback: $e");
      return true;
    }
  }
}
