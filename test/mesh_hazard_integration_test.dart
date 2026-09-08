import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:doot_flood_alert/main.dart';
import 'package:doot_flood_alert/communication/communication_manager.dart';
import 'package:doot_flood_alert/communication/alert_codec.dart';
import 'package:doot_flood_alert/services/alert_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HazardBroadcastState Tests', () {
    test('Initial hazard state has normal monitoring values', () {
      final state = HazardBroadcastState();
      expect(state.threatStatus, contains('SAFE ZONE'));
      expect(state.floodProbability, equals(15.0));
      expect(state.isCritical, isFalse);
    });

    test('Updating weather notifies listeners and updates values', () {
      final state = HazardBroadcastState();
      state.updateWeather(temp: 32.4, wind: 18.2, precip: 15.6);

      expect(state.temperature, equals(32.4));
      expect(state.windSpeed, equals(18.2));
      expect(state.precipitation, equals(15.6));
    });

    test('High flood probability marks state as critical', () {
      final state = HazardBroadcastState();
      state.updateRisk(probability: 95.5, zoneName: 'Yamuna Flood Plain');

      expect(state.isCritical, isTrue);
      expect(state.floodProbability, equals(95.5));
      expect(state.threatStatus, contains('HIGH-RISK FLOOD WARNING'));
    });
  });

  group('Offline Mesh Communication Tests', () {
    test('CommunicationManager broadcasts distress packet offline', () async {
      final comm = CommunicationManager();
      comm.startMesh();
      expect(comm.isMeshActive, isTrue);

      final packet = await comm.broadcastDistress(
        position: const LatLng(28.6692, 77.4538),
        phone: '+919999999999',
        message: 'Trapped in water',
        riskScore: 94.0,
      );

      expect(packet.alertId, startsWith('SOS_'));
      expect(packet.senderPhone, equals('+919999999999'));
      expect(packet.riskScore, equals(94.0));
      expect(comm.storedPackets.any((p) => p.alertId == packet.alertId), isTrue);

      // Verify wire encoding roundtrip
      final encoded = AlertCodec.encode(packet);
      expect(encoded.length, greaterThanOrEqualTo(16));
      final decoded = AlertCodec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.alertId, startsWith('ALERT_'));
      expect(decoded.latitude, closeTo(28.6692, 0.001));
      expect(decoded.longitude, closeTo(77.4538, 0.001));
    });

    test('BleMeshService broadcasts siren alert over mesh', () async {
      final bleService = BleMeshService();
      final success = await bleService.broadcastMeshSiren(
        const LatLng(28.6129, 77.2773),
        riskScore: 99.0,
        message: 'CRITICAL SIREN ALERT',
      );

      expect(success, isTrue);
      final packets = bleService.getReceivedPackets();
      expect(packets.any((p) => p['message'] == 'CRITICAL SIREN ALERT'), isTrue);
    });
  });

  group('AlertAudioService State Tests', () {
    test('isPlayingNotifier tracks stop state', () async {
      await AlertAudioService.stopSiren();
      expect(AlertAudioService.isPlaying, isFalse);
      expect(AlertAudioService.isPlayingNotifier.value, isFalse);
    });
  });
}
