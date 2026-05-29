// lib/sos_service_channel.dart
import 'package:flutter/services.dart';

// Defines the communication channel name (MUST match Android code)
const MethodChannel _channel = MethodChannel('com.raksha/sos_service');

class SosServiceChannel {
  // 1. Starts the background listener service
  static Future<void> startBackgroundService(List<String> gestures, List<String> voiceWords) async {
    try {
      await _channel.invokeMethod('startListener', {
        'gestures': gestures,
        'voiceWords': voiceWords,
      });
    } on PlatformException catch (e) {
      print("Failed to start service: ${e.message}");
    }
  }

  // 2. Used during Pre-SOS to cancel the trigger immediately (10s window)
  static Future<void> cancelTrigger() async {
    try {
      await _channel.invokeMethod('cancelTrigger');
    } on PlatformException catch (e) {
      print("Failed to cancel trigger: ${e.message}");
    }
  }

  // 3. Used to stop the full SOS alert loop and recording
  static Future<void> stopActiveSos() async {
    try {
      await _channel.invokeMethod('stopActiveSos');
    } on PlatformException catch (e) {
      print("Failed to stop active SOS: ${e.message}");
    }
  }
}