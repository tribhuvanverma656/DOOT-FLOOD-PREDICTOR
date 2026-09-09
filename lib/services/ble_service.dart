import 'package:flutter/services.dart';
import 'package:doot_flood_alert/services/alert_audio_service.dart';

class BleService {
  static const MethodChannel _channel =
      MethodChannel('com.example.flashfloodcommunication/ble');

  static bool _handlerRegistered = false;

  /// Registers the listener for callbacks coming FROM native Android.
  /// Call this once (e.g. from main.dart's init) so that whenever the
  /// native siren alarm turns on/off — whether because THIS device
  /// pressed Start/Stop, or because a BLE packet was RECEIVED from
  /// another device — Flutter's own siren-playing state (and therefore
  /// the Start/Stop buttons) update automatically, without the user
  /// having to press anything first.
  static void registerNativeCallbackHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSirenStateChanged':
          final bool isPlaying = call.arguments as bool;
          AlertAudioService.isPlayingNotifier.value = isPlaying;
          break;
        default:
          break;
      }
    });
  }

  /// Sends the test emergency alert over the BLE mesh
  static Future<void> sendAlert() async {
    try {
      await _channel.invokeMethod('sendAlert');
    } on PlatformException catch (e) {
      print('Failed to send alert: ${e.message}');
    }
  }

  /// Stops the alarm sound / vibration, and broadcasts a real BLE
  /// SIREN_STOP signal so other devices in the mesh stop too.
  static Future<void> stopAlertSound() async {
    try {
      await _channel.invokeMethod('stopAlertSound');
    } on PlatformException catch (e) {
      print('Failed to stop alert: ${e.message}');
    }
  }
}
