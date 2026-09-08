import 'api_service.dart';
import 'alert_audio_service.dart';
import 'hybrid_mesh_controller.dart';

class AppServices {
  static final ApiService api = ApiService();
  static final AlertAudioService audio = AlertAudioService();

  static final HybridMeshController mesh = HybridMeshController(
    api: api,
    audio: audio,
  );
}
