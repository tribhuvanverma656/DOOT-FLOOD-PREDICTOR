import 'package:flutter/services.dart';

class BleService {
  static const MethodChannel _channel =
      MethodChannel('com.example.flashfloodcommunication/ble');

  /// Sends the test emergency alert over the BLE mesh
  static Future<void> sendAlert() async {
    try {
      await _channel.invokeMethod('sendAlert');
    } on PlatformException catch (e) {
      print('Failed to send alert: ${e.message}');
    }
  }

  /// Stops the alarm sound / vibration
  static Future<void> stopAlertSound() async {
    try {
      await _channel.invokeMethod('stopAlertSound');
    } on PlatformException catch (e) {
      print('Failed to stop alert: ${e.message}');
    }
  }
}