import 'dart:typed_data';
import 'alert_packet.dart';

class AlertCodec {
  static const int maxHops = 3;

  static String canonicalAlertId(String id) {
    if (id.startsWith('ALERT_')) return id;
    return 'ALERT_${id.hashCode.toRadixString(16).toUpperCase()}';
  }

  static Uint8List encode(AlertPacket alert) {
    final bd = ByteData(16);
    // 1. Alert ID hash (4 bytes)
    bd.setInt32(0, alert.alertId.hashCode);
    // 2. Event code + severity (1 byte)
    final eventCode = (alert.eventType == 'FLASH_FLOOD' ? 1 : (alert.eventType == 'DAM_BURST' ? 2 : 3)) & 0x0F;
    final sevCode = alert.severity.clamp(0, 15) & 0x0F;
    bd.setUint8(4, (eventCode << 4) | sevCode);
    // 3. Risk score (1 byte)
    bd.setUint8(5, alert.riskScore.toInt().clamp(0, 100));
    // 4. Lat (4 bytes scaled 1e6)
    bd.setInt32(6, (alert.latitude * 1000000).toInt());
    // 5. Lon (4 bytes scaled 1e6)
    bd.setInt32(10, (alert.longitude * 1000000).toInt());
    // 6. TTL + Hop count (1 byte)
    final ttlNibble = alert.ttl.clamp(0, 15) & 0x0F;
    final hopNibble = alert.hopCount.clamp(0, 15) & 0x0F;
    bd.setUint8(14, (ttlNibble << 4) | hopNibble);
    // 7. Instruction ID (1 byte)
    bd.setUint8(15, 1);
    return bd.buffer.asUint8List();
  }

  static AlertPacket? decode(Uint8List bytes) {
    if (bytes.length < 16) return null;
    final bd = ByteData.sublistView(bytes);
    final idHash = bd.getInt32(0);
    final alertId = 'ALERT_${idHash.toRadixString(16).toUpperCase()}';
    final eventAndSev = bd.getUint8(4);
    final eventCode = (eventAndSev >> 4) & 0x0F;
    final severity = eventAndSev & 0x0F;
    final eventType = eventCode == 1 ? 'FLASH_FLOOD' : (eventCode == 2 ? 'DAM_BURST' : 'EMERGENCY_SOS');
    final riskScore = bd.getUint8(5).toDouble();
    final lat = bd.getInt32(6) / 1000000.0;
    final lon = bd.getInt32(10) / 1000000.0;
    final ttlAndHop = bd.getUint8(14);
    final ttl = (ttlAndHop >> 4) & 0x0F;
    final hopCount = ttlAndHop & 0x0F;

    return AlertPacket(
      alertId: alertId,
      eventType: eventType,
      severity: severity,
      riskScore: riskScore,
      issuedAt: DateTime.now().millisecondsSinceEpoch,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 3600000,
      latitude: lat,
      longitude: lon,
      ttl: ttl,
      hopCount: hopCount,
      originatorId: 'BLE_PEER',
      message: 'Incoming Mesh SOS Signal',
    );
  }
}
