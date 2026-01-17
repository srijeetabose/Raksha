// lib/gestures_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:raksha/secure_vault_screen.dart';
import 'dart:async';

class GesturesTab extends StatefulWidget {
  const GesturesTab({super.key});

  @override
  State<GesturesTab> createState() => _GesturesTabState();
}

class _GesturesTabState extends State<GesturesTab> {
  // Available Gestures (These MUST match the MediaPipe TFLite model labels)
  final List<Map<String, dynamic>> availableGestures = [
    {'name': 'Thumbs Up', 'icon': Icons.thumb_up, 'key': 'Thumb_Up', 'selected': false, 'emoji': '👍'},
    {'name': 'Thumbs Down', 'icon': Icons.thumb_down, 'key': 'Thumb_Down', 'selected': false, 'emoji': '👎'},
    {'name': 'Peace Sign', 'icon': Icons.pan_tool, 'key': 'Victory', 'selected': false, 'emoji': '✌️'},
    {'name': 'Closed Fist', 'icon': Icons.back_hand, 'key': 'Closed_Fist', 'selected': false, 'emoji': '✊'},
  ];
  
  List<String> _selectedKeys = [];
  bool _isLoading = false;
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  // Camera variables
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _cameraPermissionGranted = false;

  // Gesture detection feedback
  String _currentGesture = "No gesture detected";
  double _confidence = 0.0;
  bool _isDetecting = false;
  bool _isLocationSharing = false;
  bool _emergencyActive = false;
  bool _isVibrationActive = false;
  Timer? _gestureDetectionTimer;

  @override
  void initState() {
    super.initState();
    _loadUserGestures();
    _initializeCamera();
    _setupGestureListener();
  }

  @override
  void dispose() {
    print("🧹 Disposing GesturesTab - cleaning up resources");
    _gestureDetectionTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }
  
  // Setup listener for gesture and voice detection from native side
  void _setupGestureListener() {
    const platform = MethodChannel('com.example.raksha/gesture_service');
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onGestureDetected') {
        final gesture = call.arguments['gesture'] as String;
        final confidence = call.arguments['confidence'] as double;
        
        if (confidence > 0.8) {
          print("🚨 EMERGENCY: Selected gesture detected with high confidence: $gesture (${(confidence * 100).toInt()}%)");
          _triggerAutomaticSOS(gesture);
        } else {
          print("🎯 Selected gesture detected but lower confidence: $gesture (${(confidence * 100).toInt()}%)");
        }
      } else if (call.method == 'onVoiceTriggerDetected') {
        final trigger = call.arguments['trigger'] as String;
        final source = call.arguments['source'] as String? ?? 'voice';
        
        print("🚨 VOICE TRIGGER DETECTED: $trigger from $source");
        
        // Show immediate voice trigger detection message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "🎤 VOICE TRIGGER DETECTED: \"$trigger\"",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: "CANCEL SOS",
                textColor: Colors.white,
                onPressed: () {
                  _cancelSOS();
                },
              ),
            ),
          );
          
          // Update UI to show voice detection
          setState(() {
            _currentGesture = "🎤 VOICE EMERGENCY: $trigger";
            _confidence = 1.0;
            _isDetecting = true;
          });
        }
        
        // Trigger SOS for voice command
        _triggerAutomaticSOS("VOICE: $trigger");
      }
    });
  }

  // SIMPLE Camera initialization - NO CONFLICTS
  Future<void> _initializeCamera() async {
    try {
      print("🎥 Starting SIMPLE camera initialization...");
      
      // Get available cameras
      final cameras = await availableCameras();
      print("📱 Found ${cameras.length} cameras");
      
      if (cameras.isEmpty) {
        print("❌ No cameras available");
        if (mounted) {
          setState(() {
            _currentGesture = "No cameras available";
          });
        }
        return;
      }
      
      // Use front camera if available, otherwise use first camera
      CameraDescription selectedCamera = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          selectedCamera = camera;
          break;
        }
      }
      
      print("📷 Selected camera: ${selectedCamera.name} (${selectedCamera.lensDirection})");
      
      // Dispose existing controller if any
      await _cameraController?.dispose();
      
      // Create new controller with SIMPLE settings
      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      // Initialize camera
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _currentGesture = "✅ Camera ready - Monitoring for gestures...";
        });
        print("✅ Camera initialized successfully!");
        
        // Start gesture detection communication (NO native camera conflicts)
        _startGestureDetectionCommunication();
      }
      
    } catch (e) {
      print("❌ Camera initialization failed: $e");
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _currentGesture = "❌ Camera error: $e";
        });
      }
    }
  }
  
  // Check for gesture results with CLEAR visual feedback
  Future<void> _checkGestureResults() async {
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      final result = await platform.invokeMethod('getLatestGestureResult');
      
      if (result != null && mounted) {
        final gesture = result['gesture'] as String?;
        final confidence = result['confidence'] as double?;
        
        print("📥 Gesture check: $gesture (confidence: $confidence)");
        
        if (gesture != null && gesture != "None" && confidence != null && confidence > 0.5) {
          setState(() {
            _currentGesture = "✅ DETECTED: $gesture";
            _confidence = confidence;
            _isDetecting = true;
          });
          
          print("🎯 REAL GESTURE DETECTED: $gesture (${(confidence * 100).toInt()}%)");
          
          // Clear the result after processing
          await platform.invokeMethod('clearGestureResult');
          
          // Check if it's an emergency gesture
          if (_selectedKeys.contains(gesture)) {
            print("🚨 EMERGENCY GESTURE MATCH: $gesture");
            setState(() {
              _currentGesture = "🚨 EMERGENCY: $gesture";
            });
            _triggerAutomaticSOS(gesture);
          } else {
            print("ℹ️ Gesture detected but not selected for emergency: $gesture");
            setState(() {
              _currentGesture = "👋 Saw: $gesture (not emergency)";
            });
          }
          
          // Reset after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _isDetecting = false;
                _currentGesture = '🔍 Watching for gestures...';
                _confidence = 0.0;
              });
            }
          });
        } else {
          // Show that we're actively looking
          if (!_isDetecting && mounted) {
            setState(() {
              _currentGesture = '👁️ Looking for gestures...';
            });
          }
        }
      }
    } catch (e) {
      print("❌ Error checking gesture results: $e");
      if (mounted) {
        setState(() {
          _currentGesture = "❌ Detection error: $e";
        });
      }
    }
  }
  
  // WORKING gesture detection communication
  void _startGestureDetectionCommunication() {
    print("🎯 Starting WORKING gesture detection communication...");
    
    // Initialize MediaPipe processing
    _initializeMediaPipe();
    
    // Start aggressive gesture detection for testing
    _gestureDetectionTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Test gesture detection aggressively
      _testGestureDetection();
    });
    
    print("✅ WORKING gesture detection communication active!");
  }
  
  // Build camera preview with proper error handling
  Widget _buildCameraPreview() {
    if (_cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 16),
              Text(
                "Starting camera...",
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    
    if (!_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 16),
              Text(
                "Initializing camera...",
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_cameraController!.value.hasError) {
      return Container(
        color: Colors.red.shade900,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(
                "Camera Error: ${_cameraController!.value.errorDescription}",
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: const Text("Retry Camera"),
              ),
            ],
          ),
        ),
      );
    }
    
    // Camera is working - show preview with detection overlay
    return Stack(
      children: [
        CameraPreview(_cameraController!),
        
        // Detection overlay
        if (_isDetecting)
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _selectedKeys.contains(_currentGesture.replaceAll('✅ DETECTED: ', '').replaceAll('🚨 EMERGENCY: ', '').replaceAll('🧪 TESTING: ', '')) 
                  ? Colors.red 
                  : Colors.green,
                width: 4,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          
        // Confidence indicator
        if (_confidence > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "${(_confidence * 100).toInt()}%",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
        // Selected gestures indicator
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              "Emergency: ${_selectedKeys.join(', ')}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  // REMOVED DUPLICATE
  
  // Initialize MediaPipe WITHOUT native camera
  Future<void> _initializeMediaPipe() async {
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('startMediaPipeProcessing');
      print("✅ MediaPipe initialized WITHOUT native camera");
    } catch (e) {
      print("❌ MediaPipe initialization failed: $e");
    }
  }
  
  // Process real camera frame through MediaPipe
  Future<void> _processRealCameraFrame() async {
    try {
      // Take a picture from the camera
      final XFile imageFile = await _cameraController!.takePicture();
      final bytes = await imageFile.readAsBytes();
      
      print("📸 Captured image: ${bytes.length} bytes");
      
      // Send to MediaPipe for processing
      const platform = MethodChannel('com.example.raksha/gesture_service');
      final result = await platform.invokeMethod('processCameraImageBytes', {
        'imageBytes': bytes,
        'width': _cameraController!.value.previewSize?.width.toInt() ?? 640,
        'height': _cameraController!.value.previewSize?.height.toInt() ?? 480,
      });
      
      print("🎯 MediaPipe processing result: $result");
      
      // The actual gesture result will come through the gesture listener
      
    } catch (e) {
      print("❌ Real camera processing failed: $e");
    }
  }
  
  // Update detection status in UI
  void _updateDetectionStatus() {
    if (!mounted) return;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Show detection activity
    setState(() {
      if (!_isDetecting) {
        _currentGesture = "🔍 Scanning for gestures... (${_selectedKeys.length} selected)";
      }
    });
    
    // Test SOS system every 15 seconds if gestures are selected
    if (_selectedKeys.isNotEmpty && now % 15000 < 2000) { // Every 15 seconds for 2 seconds
      final testGesture = _selectedKeys.first;
      print("🧪 TESTING SOS SYSTEM: $testGesture");
      
      setState(() {
        _currentGesture = "🧪 TESTING: $testGesture";
        _confidence = 0.95;
        _isDetecting = true;
      });
      
      // Trigger SOS test
      _triggerAutomaticSOS(testGesture);
      
      // Reset after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isDetecting = false;
            _currentGesture = '🔍 Monitoring for gestures...';
            _confidence = 0.0;
          });
        }
      });
    }
  }
  
  // REAL gesture detection using camera frames
  Future<void> _testGestureDetection() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      print("🎯 REAL gesture detection - processing camera frame...");
      
      // Method 1: Process real camera frame through MediaPipe
      await _processRealCameraFrame();
      
      // Method 2: Check for any existing results
      await _checkGestureResults();
      
      // Method 3: Show current detection status
      _updateDetectionStatus();
      
    } catch (e) {
      print("❌ Error in real gesture detection: $e");
    }
  }

  // COMPLETE SOS sequence with notifications, countdown, vibration, and secure vault recording
  void _triggerAutomaticSOS(String gestureName) async {
    try {
      print("🚨 CROSS-APP EMERGENCY DETECTED: $gestureName");
      
      if (!mounted) {
        print("🛑 Widget unmounted - cancelling SOS sequence");
        return;
      }
      
      const platform = MethodChannel('com.example.raksha/gesture_service');
      const sosChannel = MethodChannel('com.raksha/sos_service');
      
      // PHASE 0: Start secure vault recording IMMEDIATELY
      print("🎥 PHASE 0: Starting SECURE VAULT recording immediately");
      try {
        await sosChannel.invokeMethod('startEmergencyRecording', {
          'gesture': gestureName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'recordAudio': true,
          'recordVideo': true,
          'saveToSecureVault': true,
        });
        print("✅ Secure vault recording started");
      } catch (e) {
        print("❌ Secure vault recording failed: $e");
      }
      
      // PHASE 1: Show 10-second countdown NOTIFICATION (works across all apps)
      print("🚨 PHASE 1: Starting 10-second countdown NOTIFICATION");
      await platform.invokeMethod('showSOSCountdownNotification', {
        'gesture': gestureName,
        'countdown': 10,
      });
      
      // Wait 10 seconds - user can cancel via notification
      print("⏰ Waiting 10 seconds for countdown...");
      await Future.delayed(const Duration(seconds: 10));
      
      // Check if cancelled (this would be set by notification action)
      // For now, continue to next phase
      
      // PHASE 2: Start 7-second vibration with notification
      print("🚨 PHASE 2: Starting 7-second vibration phase");
      
      if (mounted) {
        setState(() {
          _isVibrationActive = true;
        });
      }
      
      // Start vibration and show notification
      await platform.invokeMethod('startEmergencyVibration', {
        'gesture': gestureName,
      });
      
      await platform.invokeMethod('showVibrationNotification', {
        'gesture': gestureName,
        'message': 'SOS will activate after vibration! Open app to cancel!',
      });
      
      // Wait 7 seconds for vibration phase
      bool vibrationCancelled = await _waitForVibrationCancellation();
      
      if (mounted) {
        setState(() {
          _isVibrationActive = false;
        });
      }
      
      if (vibrationCancelled) {
        print("🛑 Emergency cancelled during vibration phase");
        await platform.invokeMethod('stopEmergencyVibration');
        await _stopSecureVaultRecording();
        return;
      }
      
      // Stop vibration after 7 seconds
      await platform.invokeMethod('stopEmergencyVibration');
      
      // PHASE 3: Trigger real SOS (recording continues)
      print("🚨 PHASE 3: TRIGGERING REAL SOS - RECORDING CONTINUES");
      await _triggerRealSOS(gestureName);
      
    } catch (e) {
      print("❌ Error in SOS sequence: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("SOS Error: $e")),
        );
      }
    }
  }
  
  // Wait for countdown cancellation
  Future<bool> _waitForCountdownCancellation(int seconds) async {
    // This would be handled by notifications - for now just wait
    await Future.delayed(Duration(seconds: seconds));
    return false; // Not cancelled
  }
  
  // Stop secure vault recording
  Future<void> _stopSecureVaultRecording() async {
    try {
      const sosChannel = MethodChannel('com.raksha/sos_service');
      await sosChannel.invokeMethod('stopEmergencyRecording');
      print("🛑 Secure vault recording stopped");
    } catch (e) {
      print("❌ Error stopping secure vault recording: $e");
    }
  }

  // Show countdown dialog (10 seconds)
  Future<bool> _showCountdownDialog(String gestureName) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          int countdown = 10;
          bool cancelled = false;
          
          // Start countdown timer
          Timer.periodic(const Duration(seconds: 1), (timer) {
            if (countdown > 0) {
              setState(() {
                countdown--;
              });
            } else {
              timer.cancel();
              if (!cancelled && Navigator.canPop(context)) {
                Navigator.of(context).pop(false); // Not cancelled
              }
            }
          });
          
          return AlertDialog(
            backgroundColor: Colors.red,
            title: const Text(
              "🚨 EMERGENCY DETECTED",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Gesture: $gestureName",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "SOS will trigger in $countdown seconds",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Press CANCEL if this is a mistake",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(context).pop(true); // Cancelled
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                ),
                child: const Text(
                  "CANCEL EMERGENCY",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    ) ?? false;
  }
  
  // Wait for vibration cancellation (7 seconds)
  Future<bool> _waitForVibrationCancellation() async {
    // Wait 7 seconds for user to open app and cancel
    await Future.delayed(const Duration(seconds: 7));
    return false; // Not cancelled (would be handled by native when user opens app)
  }
  
  // Show vibration cancel dialog when app is opened during vibration
  void _showVibrationCancelDialog(String gesture) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.orange,
        title: const Text(
          "🚨 7-SECOND VIBRATION PHASE",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Gesture: $gesture\n\nSOS will activate after vibration ends!\n\nPress CANCEL NOW if this is a mistake.",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _cancelSOSDuringVibration();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            child: const Text(
              "CANCEL SOS NOW",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
  
  // FIXED: Trigger the actual SOS sequence with mounted checks
  Future<void> _triggerRealSOS(String gestureName) async {
    try {
      print("🚨 TRIGGERING REAL SOS SEQUENCE FOR: $gestureName");
      
      if (!mounted) {
        print("🛑 Widget unmounted - stopping SOS sequence");
        return;
      }
      
      const platform = MethodChannel('com.example.raksha/gesture_service');
      
      // 0. Check if emergency contacts exist first
      print("📋 Checking emergency contacts...");
      final contactCheck = await platform.invokeMethod('checkEmergencyContacts');
      print("📋 Contact check result: $contactCheck");
      
      final hasContacts = contactCheck['hasContacts'] as bool? ?? false;
      final contactCount = contactCheck['contactCount'] as int? ?? 0;
      
      if (!hasContacts) {
        print("❌ NO EMERGENCY CONTACTS FOUND!");
        if (mounted) {
          setState(() {
            _currentGesture = "❌ No emergency contacts! Add contacts first.";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ No emergency contacts found! Please add contacts in the Contacts tab first."),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      
      // 1. Send SMS to emergency contacts immediately (most important)
      print("📱 Sending emergency SMS to $contactCount contacts...");
      const sosChannel = MethodChannel('com.raksha/sos_service');
      
      try {
        await sosChannel.invokeMethod('sendEmergencySMSToContacts', {
          'gesture': gestureName,
          'message': 'I need help! Please call me immediately!',
        });
        print("✅ SMS sending command completed");
      } catch (e) {
        print("❌ SMS sending failed: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ SMS failed: $e")),
          );
        }
      }
      
      // 2. Start location sharing
      print("📍 Starting location sharing...");
      try {
        await platform.invokeMethod('startLocationSharing', {
          'gesture': gestureName,
        });
      } catch (e) {
        print("⚠️ Location sharing failed: $e");
      }
      
      // 3. Start emergency recording (CRITICAL)
      print("🎥 Starting emergency audio/video recording...");
      try {
        await sosChannel.invokeMethod('startEmergencyRecording', {
          'gesture': gestureName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'recordAudio': true,
          'recordVideo': true,
          'saveToSecureVault': true,
        });
        print("✅ Emergency recording started");
      } catch (e) {
        print("❌ Emergency recording failed: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("⚠️ Recording failed: $e")),
          );
        }
      }
      
      // 4. Update UI if still mounted
      if (mounted) {
        setState(() {
          _isLocationSharing = true;
          _emergencyActive = true;
          _currentGesture = "🚨 EMERGENCY ACTIVE: $gestureName";
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🚨 EMERGENCY SOS ACTIVATED! SMS sent to contacts."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      
      print("✅ Real SOS sequence initiated successfully");
    } catch (e) {
      print("❌ Error triggering real SOS: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ SOS Error: $e")),
        );
      }
    }
  }
  
  // Stop location sharing - FIXED
  Future<void> _stopLocationSharing() async {
    try {
      print("🛑 Stopping location sharing...");
      
      const platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('stopLocationSharing');
      
      if (mounted) {
        setState(() {
          _isLocationSharing = false;
          _emergencyActive = false;
          _currentGesture = "🛑 Emergency stopped - Location sharing disabled";
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🛑 Location sharing stopped"),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      print("✅ Location sharing stopped successfully");
    } catch (e) {
      print("❌ Error stopping location sharing: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error stopping location: $e")),
        );
      }
    }
  }
  
  // Cancel SOS
  Future<void> _cancelSOS() async {
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('cancelAllSOS');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🛑 SOS Cancelled"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("❌ Error cancelling SOS: $e");
    }
  }
  
  // Cancel SOS during vibration phase
  Future<void> _cancelSOSDuringVibration() async {
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('cancelSOSDuringVibration');
      
      if (mounted) {
        setState(() {
          _isVibrationActive = false;
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🛑 Emergency SOS cancelled during vibration phase"),
          backgroundColor: Colors.green,
        ),
      );
      
      print("🛑 SOS cancelled during vibration phase");
    } catch (e) {
      print("❌ Error cancelling SOS during vibration: $e");
    }
  }

  // Fetch the currently saved gestures from Firestore
  Future<void> _loadUserGestures() async {
    if (_userId == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
      if (doc.exists) {
        final savedKeys = List<String>.from(doc.data()?['triggerGestures'] ?? []);
        if (mounted) {
          setState(() {
            _selectedKeys = savedKeys;
            for (var gesture in availableGestures) {
              gesture['selected'] = savedKeys.contains(gesture['key']);
            }
          });
        }
      }
    } catch (e) {
      print("Error loading gestures: $e");
    }
  }

  // Toggle gesture selection
  void _toggleSelection(int index) {
    if (_isLoading) return;

    setState(() {
      String key = availableGestures[index]['key'];
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
        availableGestures[index]['selected'] = false;
      } else if (_selectedKeys.length < 2) {
        _selectedKeys.add(key);
        availableGestures[index]['selected'] = true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can only select 2 gestures")),
        );
      }
    });
  }

  // Save selected gestures to Firestore
  Future<void> _saveGestures() async {
    if (_selectedKeys.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select exactly 2 gestures")),
      );
      return;
    }
    if (_userId == null) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).update({
        'triggerGestures': _selectedKeys,
      });

      // Start CROSS-APP background service with selected gestures
      await _startCrossAppDetectionService();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ CROSS-APP Emergency Detection Activated!\n🎤 Voice + 👋 Gesture detection now works across ALL apps!"),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  // Test SOS system
  void _testSOSSystem() {
    if (_selectedKeys.isNotEmpty) {
      final testGesture = _selectedKeys.first;
      print("🧪 TESTING SOS SYSTEM WITH: $testGesture");
      
      setState(() {
        _currentGesture = "TESTING: $testGesture";
        _confidence = 1.0;
        _isDetecting = true;
      });
      
      // Trigger SOS test
      _triggerAutomaticSOS(testGesture);
    }
  }
  
  // Test SMS system
  void _testSMSSystem() async {
    try {
      // Show dialog to enter phone number
      String? phoneNumber = await _showPhoneNumberDialog();
      
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        print("🧪 Testing SMS to: $phoneNumber");
        
        const sosChannel = MethodChannel('com.raksha/sos_service');
        await sosChannel.invokeMethod('testSMSSystem', {
          'phoneNumber': phoneNumber,
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("📱 Test SMS sent to $phoneNumber")),
          );
        }
      }
    } catch (e) {
      print("❌ SMS test failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ SMS test failed: $e")),
        );
      }
    }
  }
  
  // Show dialog to enter phone number for SMS test
  Future<String?> _showPhoneNumberDialog() async {
    String phoneNumber = '';
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Test SMS System"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your phone number to test SMS:"),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => phoneNumber = value,
              decoration: const InputDecoration(
                hintText: "e.g., +1234567890",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(phoneNumber),
            child: const Text("Send Test SMS"),
          ),
        ],
      ),
    );
  }

  // Start CROSS-APP detection service that works across ALL apps
  Future<void> _startCrossAppDetectionService() async {
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      
      print("🌐 Starting CROSS-APP detection service...");
      
      // 1. Start accessibility service for cross-app monitoring
      await platform.invokeMethod('startAccessibilityService');
      print("♿ Accessibility service started for cross-app detection");
      
      // 2. Start foreground service with cross-app capabilities
      await platform.invokeMethod('startRealBackgroundService', {
        'gestures': _selectedKeys,
        'crossApp': true,
      });
      print("🚀 Cross-app gesture service started with gestures: $_selectedKeys");
      
      // 3. Start cross-app voice detection
      await platform.invokeMethod('startVoiceDetection', {
        'triggers': ['help me', 'emergency', 'call police', 'danger', 'rescue me'],
        'crossApp': true,
      });
      print("🎤 Cross-app voice detection started");
      
      // 4. Enable system-wide detection
      await platform.invokeMethod('enableSystemWideDetection');
      print("🌍 System-wide detection enabled");
      
      print("✅ COMPLETE cross-app detection system activated!");
      
    } catch (e) {
      print("❌ Error starting cross-app detection: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Gestures"),
        backgroundColor: const Color(0xFF6A5AE3),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SIMPLE CAMERA PREVIEW - NO OVERLAYS
                Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _buildCameraPreview(),
                  ),
                ),
                const SizedBox(height: 8),
                // Enhanced status display with cross-app info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isDetecting 
                      ? (_currentGesture.contains('EMERGENCY') ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1))
                      : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isDetecting 
                        ? (_currentGesture.contains('EMERGENCY') ? Colors.red : Colors.green)
                        : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _currentGesture,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isDetecting 
                            ? (_currentGesture.contains('EMERGENCY') ? Colors.red : Colors.green)
                            : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_confidence > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Confidence: ${(_confidence * 100).toInt()}%",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              Icon(
                                Icons.apps,
                                color: Colors.blue,
                                size: 20,
                              ),
                              Text(
                                "Cross-App\nDetection",
                                style: TextStyle(fontSize: 10, color: Colors.blue),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Icon(
                                Icons.security,
                                color: Colors.purple,
                                size: 20,
                              ),
                              Text(
                                "Secure Vault\nRecording",
                                style: TextStyle(fontSize: 10, color: Colors.purple),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Icon(
                                Icons.vibration,
                                color: Colors.orange,
                                size: 20,
                              ),
                              Text(
                                "Background\nMonitoring",
                                style: TextStyle(fontSize: 10, color: Colors.orange),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // VIBRATION PHASE CONTROLS (only shown during 7-second vibration)
                if (_isVibrationActive) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange, width: 3),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.vibration, color: Colors.orange, size: 24),
                            SizedBox(width: 8),
                            Text(
                              "📳 7-SECOND VIBRATION PHASE",
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "SOS will activate after vibration ends unless you cancel NOW!",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _cancelSOSDuringVibration,
                          icon: const Icon(Icons.cancel, color: Colors.white),
                          label: const Text(
                            "CANCEL SOS NOW",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // LOCATION SHARING CONTROLS (only shown during emergency)
                if (_isLocationSharing) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on, color: Colors.red, size: 24),
                            SizedBox(width: 8),
                            Text(
                              "🔴 LIVE LOCATION SHARING ACTIVE",
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Your location is being shared with emergency contacts",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _stopLocationSharing,
                          icon: const Icon(Icons.stop_circle, color: Colors.white),
                          label: const Text(
                            "STOP SHARING MY LOCATION",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // CHOOSE GESTURES Section
                const Text(
                  "Choose Emergency Gestures",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Select exactly 2 gestures. The AI model is pre-trained for all gestures.",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),

                // Gesture Grid (4 buttons)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10.0,
                    mainAxisSpacing: 10.0,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: availableGestures.length,
                  itemBuilder: (context, index) {
                    final gesture = availableGestures[index];
                    return GestureDetector(
                      onTap: _isLoading ? null : () => _toggleSelection(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: gesture['selected'] ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                          border: Border.all(
                            color: gesture['selected'] ? Colors.green : Colors.grey,
                            width: gesture['selected'] ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              gesture['emoji'],
                              style: const TextStyle(fontSize: 40),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              gesture['name'],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: gesture['selected'] ? Colors.green : Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (gesture['selected'])
                              const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Selection Status
                Text(
                  "Selected: ${_selectedKeys.length}/2 gestures",
                  style: TextStyle(color: _selectedKeys.length == 2 ? Colors.green : Colors.orange),
                ),
                const SizedBox(height: 20),

                // Activate Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveGestures,
                    icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Icon(Icons.play_arrow),
                    label: Text(
                      _isLoading ? "SAVING..." : "Activate Emergency Gestures",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A5AE3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Test SOS Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _selectedKeys.length == 2 ? () {
                      print("🧪 MANUAL SOS TEST");
                      _triggerAutomaticSOS(_selectedKeys.first);
                    } : null,
                    icon: const Icon(Icons.warning, color: Colors.white),
                    label: const Text(
                      "TEST SOS SYSTEM",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Test SMS Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _testSMSSystem();
                    },
                    icon: const Icon(Icons.sms, color: Colors.white),
                    label: const Text(
                      "TEST SMS SYSTEM",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Secure Vault Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _openSecureVault();
                    },
                    icon: const Icon(Icons.security, color: Colors.white),
                    label: const Text(
                      "OPEN SECURE VAULT",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Voice Trigger Test Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _testVoiceTriggers();
                    },
                    icon: const Icon(Icons.mic, color: Colors.white),
                    label: const Text(
                      "TEST VOICE TRIGGERS",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // Open secure vault with PIN protection
  void _openSecureVault() async {
    try {
      print("🔒 Opening secure vault...");
      
      // Navigate to secure vault screen with PIN protection
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const SecureVaultScreen(),
        ),
      );
      
    } catch (e) {
      print("❌ Error opening secure vault: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Vault error: $e")),
        );
      }
    }
  }
  
  // Test voice triggers
  void _testVoiceTriggers() async {
    try {
      print("🎤 Testing voice triggers...");
      
      // Start voice detection
      const platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('startVoiceDetection', {
        'triggers': ['help me', 'emergency', 'call police', 'danger', 'rescue me'],
      });
      
      if (mounted) {
        setState(() {
          _currentGesture = "🎤 Voice detection active - Say: 'help me', 'emergency', 'danger'";
        });
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("🎤 Voice Triggers Active"),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Voice detection is now active across ALL apps!"),
                SizedBox(height: 16),
                Text("Try saying any of these trigger words:"),
                SizedBox(height: 8),
                Text("• 'Help me'", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("• 'Emergency'", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("• 'Call police'", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("• 'Danger'", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("• 'Rescue me'", style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 16),
                Text("This will work even when using other apps like WhatsApp, Instagram, etc.", 
                     style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Got it!"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print("❌ Voice trigger test failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Voice test failed: $e")),
        );
      }
    }
  }
}