// lib/voice_detection_service.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VoiceDetectionService {
  static final VoiceDetectionService _instance = VoiceDetectionService._internal();
  factory VoiceDetectionService() => _instance;
  VoiceDetectionService._internal();

  static const MethodChannel _channel = MethodChannel('com.example.raksha/gesture_service');
  bool _isListening = false;
  bool _isInitialized = false;
  List<String> _triggerWords = [];
  Function(String)? _onTriggerDetected;

  // Initialize voice detection using native Android implementation
  Future<bool> initialize() async {
    try {
      await _loadTriggerWords();
      _isInitialized = true;
      print("✅ Voice detection initialized with native Android speech recognition");
      return true;
    } catch (e) {
      print("❌ Failed to initialize voice detection: $e");
      return false;
    }
  }

  // Load trigger words from Firestore
  Future<void> _loadTriggerWords() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          final words = doc.data()?['voiceTriggers'] as List?;
          _triggerWords = words?.cast<String>() ?? ['help me', 'emergency', 'call police'];
          print("🎤 Loaded trigger words: $_triggerWords");
        }
      }
    } catch (e) {
      print("❌ Error loading trigger words: $e");
      // Default trigger words if loading fails
      _triggerWords = ['help me', 'emergency', 'call police'];
    }
  }
  
  // Reload trigger words (call this when user updates triggers)
  Future<void> reloadTriggerWords() async {
    await _loadTriggerWords();
    print("🔄 Trigger words reloaded: $_triggerWords");
  }

  // Start continuous listening using native Android implementation
  Future<void> startListening({Function(String)? onTriggerDetected}) async {
    if (!_isInitialized) {
      print("❌ Voice detection not initialized");
      return;
    }

    _onTriggerDetected = onTriggerDetected;

    try {
      // Start native Android voice detection
      await _channel.invokeMethod('startVoiceDetection', {
        'triggers': _triggerWords,
      });
      
      _isListening = true;
      print("🎤 Started native Android voice listening for triggers: $_triggerWords");
      
    } catch (e) {
      print("❌ Error starting native voice listening: $e");
    }
  }

  // Stop listening
  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopVoiceDetection');
      _isListening = false;
      print("🛑 Stopped native voice listening");
    } catch (e) {
      print("❌ Error stopping voice listening: $e");
    }
  }

  // Handle voice trigger detected (called from MainActivity)
  void onVoiceTriggerDetected(String trigger) {
    print("🚨 VOICE TRIGGER DETECTED: $trigger");
    _onTriggerDetected?.call(trigger);
  }

  // Check if voice triggers are set up
  bool get isSetUp => _triggerWords.isNotEmpty;
  
  // Get trigger words
  List<String> get triggerWords => _triggerWords;
  
  // Check if listening
  bool get isListening => _isListening;
}