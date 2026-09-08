import '../communication/communication_manager.dart';
import '../communication/alert_packet.dart';
import 'api_service.dart';
import 'alert_audio_service.dart';

class HybridMeshController {
  final ApiService api;
  final AlertAudioService audio;
  final CommunicationManager communication = CommunicationManager();

  HybridMeshController({
    required this.api,
    required this.audio,
  });

  Stream<AlertPacket> get onAlertReceived => communication.onAlertReceived;
  List<AlertPacket> get storedPackets => communication.storedPackets;
}
