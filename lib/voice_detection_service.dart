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
      // debug removed
      return true;
    } catch (e) {
      // debug removed
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
          // debug removed
        }
      }
    } catch (e) {
      // debug removed
      // Default trigger words if loading fails
      _triggerWords = ['help me', 'emergency', 'call police'];
    }
  }
  
  // Reload trigger words (call this when user updates triggers)
  Future<void> reloadTriggerWords() async {
    await _loadTriggerWords();
    // debug removed
  }

  // Start continuous listening using native Android implementation
  Future<void> startListening({Function(String)? onTriggerDetected}) async {
    if (!_isInitialized) {
      // debug removed
      return;
    }

    _onTriggerDetected = onTriggerDetected;

    try {
      // Start native Android voice detection
      await _channel.invokeMethod('startVoiceDetection', {
        'triggers': _triggerWords,
      });
      
      _isListening = true;
      // debug removed
      
    } catch (e) {
      // debug removed
    }
  }

  // Stop listening
  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopVoiceDetection');
      _isListening = false;
      // debug removed
    } catch (e) {
      // debug removed
    }
  }

  // Handle voice trigger detected (called from MainActivity)
  void onVoiceTriggerDetected(String trigger) {
    // debug removed
    _onTriggerDetected?.call(trigger);
  }

  // Check if voice triggers are set up
  bool get isSetUp => _triggerWords.isNotEmpty;
  
  // Get trigger words
  List<String> get triggerWords => _triggerWords;
  
  // Check if listening
  bool get isListening => _isListening;
}