// lib/user_safety_dashboard.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Navigation imports 
import 'package:raksha/onboarding_gesture_screen.dart'; 
import 'package:raksha/onboarding_contacts_screen.dart';
import 'package:raksha/onboarding_voice_screen.dart';
import 'package:raksha/secure_vault_screen.dart';
import 'package:raksha/gestures_tab.dart'; 
import 'package:raksha/contacts_tab.dart'; 
import 'package:raksha/settings_tab.dart';
import 'package:raksha/sos_service_channel.dart';
import 'package:raksha/voice_detection_service.dart';

class UserSafetyDashboard extends StatefulWidget {
  const UserSafetyDashboard({super.key});

  @override
  State<UserSafetyDashboard> createState() => _UserSafetyDashboardState();
}

class _UserSafetyDashboardState extends State<UserSafetyDashboard> {
  // Map and Location State
  late MapController _mapController;
  Position? _currentPosition;
  String _lastUpdated = '00:00:00';
  StreamSubscription<Position>? _positionStreamSubscription;
  
  // Navigation State
  final int _currentIndex = 0; 
  // SOS Status Variables
  bool _isSosActive = false;
  bool _isPreSosCounting = false;
  int _emergencyContactCount = 0;
  
  // Voice detection
  final VoiceDetectionService _voiceService = VoiceDetectionService();
  bool _isVoiceSetUp = false;
  
  // Live location sharing
  String? _currentEmergencySessionId; 

  // List of tabs corresponding to the bottom navigation bar
  final List<Widget> _tabs = const [
    Placeholder(), // Replaced by _HomeMapContentView when _currentIndex == 0
    GesturesTab(),     
    ContactsTab(),     
    SettingsTab(),     
  ];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _startLocationStream();
    _startBackgroundServices();
    _loadEmergencyContactCount();
    _initializeVoiceDetection();
  }
  
  // Load emergency contact count from Firestore
  Future<void> _loadEmergencyContactCount() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          final contacts = doc.data()?['emergencyContacts'] as List?;
          if (mounted) {
            setState(() {
              _emergencyContactCount = contacts?.length ?? 0;
            });
          }
        }
      }
    } catch (e) {
      print("Error loading contact count: $e");
    }
  }
  
  // Initialize voice detection
  Future<void> _initializeVoiceDetection() async {
    try {
      print("🎤 Initializing NATIVE voice detection...");
      
      // Load voice triggers from Firestore
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          final triggers = doc.data()?['triggerVoiceWords'] as List? ?? doc.data()?['voiceTriggers'] as List?;
          if (triggers != null && triggers.isNotEmpty) {
            setState(() {
              _isVoiceSetUp = true;
            });
            
            // Start native voice detection
            const platform = MethodChannel('com.example.raksha/gesture_service');
            await platform.invokeMethod('startVoiceDetection', {
              'triggers': triggers,
            });
            
            print("🎤 Native voice detection started with triggers: $triggers");
          } else {
            print("⚠️ No voice triggers set up");
          }
        }
      }
    } catch (e) {
      print("❌ Error initializing voice detection: $e");
    }
  }
  
  // Test voice detection manually
  void _testVoiceDetection() async {
    if (!_isVoiceSetUp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Voice triggers not set up. Go to Voice Triggers to set them up first."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎤 Voice Detection Test'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Say one of your trigger words:'),
            const SizedBox(height: 10),
            ...(_voiceService.triggerWords.map((word) => 
              Chip(label: Text(word, style: const TextStyle(fontWeight: FontWeight.bold)))
            )),
            const SizedBox(height: 10),
            const Text('The system is listening...'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    // Start temporary listening for test
    await _voiceService.startListening(
      onTriggerDetected: (trigger) {
        Navigator.of(context).pop(); // Close test dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Voice trigger '$trigger' detected successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      },
    );
  }

  // Trigger SOS from voice detection
  void _triggerVoiceSOS(String trigger) {
    print("🚨 VOICE SOS TRIGGERED: $trigger");
    
    // Show immediate alert
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('🚨 VOICE TRIGGER DETECTED!'),
          content: Text('Voice trigger "$trigger" detected!\n\nSOS will activate in 10 seconds.\nTap CANCEL to stop.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                print("🛑 Voice SOS cancelled by user");
              },
              child: const Text('CANCEL', style: TextStyle(color: Colors.red, fontSize: 18)),
            ),
          ],
        ),
      );
      
      // Auto-trigger SOS after 10 seconds
      Timer(const Duration(seconds: 10), () {
        if (mounted) {
          Navigator.of(context).pop(); // Close dialog
          _triggerSos(); // Trigger full SOS
        }
      });
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _locationSharingTimer?.cancel();
    super.dispose();
  }

  // --- Background Service Logic ---
  void _startBackgroundServices() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      // Load user settings from Firestore
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final isBackgroundEnabled = data['isBackgroundRunningEnabled'] ?? true;
        final isGestureEnabled = data['isGestureDetectionEnabled'] ?? false;
        final isVoiceEnabled = data['isVoiceDetectionEnabled'] ?? false;
        
        if (isBackgroundEnabled && (isGestureEnabled || isVoiceEnabled)) {
          // Get user's selected gestures and voice words from Firestore
          final selectedGestures = isGestureEnabled 
              ? (data['triggerGestures'] as List<dynamic>?)?.cast<String>() ?? <String>[]
              : <String>[];
          final voiceWords = isVoiceEnabled 
              ? (data['triggerVoiceWords'] as List<dynamic>?)?.cast<String>() ?? <String>[]
              : <String>[];
          
          await SosServiceChannel.startBackgroundService(selectedGestures, voiceWords);
          print('Background service started with gestures: $selectedGestures, voice words: $voiceWords');
        }
      }
    } catch (e) {
      print('Failed to start background services: $e');
    }
  }

  // --- Location Service Logic ---
  void _startLocationStream() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _lastUpdated = 'Service Disabled');
      return;
    }

    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _lastUpdated = 'Permission Denied');
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _lastUpdated = 'Permission Denied Forever');
      return;
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation, 
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _lastUpdated = TimeOfDay.now().format(context);
          
          if (_currentIndex == 0) {
             _mapController.move(
                LatLng(position.latitude, position.longitude),
                _mapController.camera.zoom
            );
          }
        });
      }
    }, onError: (e) {
      if (mounted) setState(() => _lastUpdated = 'Error: ${e.toString()}');
      print('Location stream error: $e');
    });
  }
  
  // --- Test Alert Function ---
  void _testAlert() async {
    // Show instruction dialog instead of sending immediately
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🧪 Test Alert Mode'),
        content: const Text(
          'Test Alert is now ACTIVE!\n\n'
          '• Perform one of your chosen gestures\n'
          '• OR say your voice trigger phrase\n\n'
          'The system will detect it and send a test message to your emergency contacts.\n\n'
          'This will test the actual detection system.'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startTestMode();
            },
            child: const Text('Start Test'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
  
  // Start test mode - listen for actual gestures/voice
  void _startTestMode() async {
    try {
      // Enable test mode in the gesture detection system
      const platform = MethodChannel('com.raksha/sos_service');
      await platform.invokeMethod('enableTestMode');
      
      // Show persistent notification that test mode is active
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🧪 TEST MODE ACTIVE - Perform your gesture or voice trigger"),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 10),
        ),
      );
      
      print("🧪 Test mode activated - waiting for real gesture/voice detection");
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Failed to start test mode: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // --- SOS Logic ---
  void _triggerSos() {
    if (_isSosActive || _isPreSosCounting) return;
    
    // Check for permissions just before triggering
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location not ready. Check permissions."))
      );
      return;
    }
    
    setState(() {
      _isPreSosCounting = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("SOS Triggered! 10s Window to Cancel.")),
    );

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isPreSosCounting) {
        setState(() {
          _isPreSosCounting = false;
          _isSosActive = true;
        });
        
        // Send emergency SMS with live location
        _sendEmergencySMS();
        
        // Start continuous location sharing
        _startContinuousLocationSharing();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🚨 SOS ACTIVE! Emergency alerts sent with live location.")),
        );
      }
    });
  }
  
  void _stopActiveSos() {
    print("🛑 STOP LOCATION SHARING BUTTON PRESSED");
    
    setState(() {
      _isSosActive = false;
      _isPreSosCounting = false;
    });
    
    print("🛑 State updated: _isSosActive = $_isSosActive");
    
    // Stop continuous location sharing
    _stopContinuousLocationSharing();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ SOS STOPPED. Location sharing ended. You are safe.")),
    );
  }

  // Send initial emergency SMS and start live location sharing
  Future<void> _sendEmergencySMS() async {
    if (_currentPosition == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get user's emergency contacts
      final contactsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('emergency_contacts')
          .get();

      if (contactsSnapshot.docs.isEmpty) {
        print("No emergency contacts found");
        return;
      }

      // Create Firebase live location sharing document
      final emergencySessionId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Store emergency session in Firebase
      await FirebaseFirestore.instance
          .collection('emergency_sessions')
          .doc(emergencySessionId)
          .set({
        'userId': user.uid,
        'startTime': FieldValue.serverTimestamp(),
        'isActive': true,
        'currentLocation': {
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        },
        'emergencyContacts': contactsSnapshot.docs.map((doc) => {
          'contactId': doc.id,
          'name': doc.data()['name'],
          'phone': doc.data()['phone'],
        }).toList(),
      });

      // Create live location sharing link using your Firebase project
      final liveLocationUrl = "https://raksha-11563.web.app/live-location/$emergencySessionId";
      
      // Get current time
      final now = DateTime.now();
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      
      // Create emergency message with LIVE location link
      final emergencyMessage = """
🚨 EMERGENCY ALERT - RAKSHA SAFETY APP 🚨

I NEED IMMEDIATE HELP!

📍 MY LIVE LOCATION (REAL-TIME):
$liveLocationUrl

🕐 Emergency Started: $timeStr
📱 This link shows my LIVE location that updates automatically

⚠️ IMPORTANT: This live location will continue updating until I manually stop it from my phone.

Please call me immediately or contact emergency services if you cannot reach me.

- Sent automatically by Raksha Safety App
""";

      // Send SMS to all emergency contacts
      for (var contactDoc in contactsSnapshot.docs) {
        final contactData = contactDoc.data();
        final phoneNumber = contactData['phone'] as String?;
        
        if (phoneNumber != null && phoneNumber.isNotEmpty) {
          await _sendSMSMessage(phoneNumber, emergencyMessage);
          print("📱 Emergency SMS with LIVE location sent to: $phoneNumber");
        }
      }

      // Store the session ID for later use
      _currentEmergencySessionId = emergencySessionId;
      
      print("✅ Emergency SMS with LIVE location sent to ${contactsSnapshot.docs.length} contacts");
      
    } catch (e) {
      print("❌ Error sending emergency SMS: $e");
    }
  }

  // Send SMS using platform channel
  Future<void> _sendSMSMessage(String phoneNumber, String message) async {
    try {
      const platform = MethodChannel('com.raksha/sos_service');
      await platform.invokeMethod('sendEmergencySMS', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
    } catch (e) {
      print("❌ Failed to send SMS to $phoneNumber: $e");
    }
  }

  // Start continuous LIVE location sharing to Firebase (every 10 seconds)
  Timer? _locationSharingTimer;
  
  void _startContinuousLocationSharing() {
    print("🌍 Starting LIVE location sharing to Firebase...");
    
    // Update Firebase with live location every 10 seconds
    _locationSharingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isSosActive || _currentEmergencySessionId == null) {
        timer.cancel();
        return;
      }
      
      // Get fresh location
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        
        setState(() {
          _currentPosition = position;
          _lastUpdated = "Live: ${DateTime.now().toString().substring(11, 16)}";
        });

        // Update Firebase with new location
        await _updateLiveLocationInFirebase(position);
        
      } catch (e) {
        print("❌ Error updating live location: $e");
      }
    });
  }

  // Stop continuous location sharing
  void _stopContinuousLocationSharing() {
    print("🛑 Stopping continuous location sharing...");
    
    if (_locationSharingTimer != null) {
      _locationSharingTimer?.cancel();
      _locationSharingTimer = null;
      print("✅ Location sharing timer cancelled");
    } else {
      print("⚠️ No active location sharing timer found");
    }
    
    // End Firebase emergency session
    _endEmergencySession();
    
    // Send final message to contacts
    _sendLocationStoppedMessage();
    
    print("🛑 LIVE location sharing completely stopped");
  }

  // Update live location in Firebase (real-time for emergency contacts)
  Future<void> _updateLiveLocationInFirebase(Position position) async {
    if (_currentEmergencySessionId == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('emergency_sessions')
          .doc(_currentEmergencySessionId!)
          .update({
        'currentLocation': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'accuracy': position.accuracy,
          'speed': position.speed,
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      print("📍 Live location updated in Firebase: ${position.latitude}, ${position.longitude}");
      
    } catch (e) {
      print("❌ Error updating live location in Firebase: $e");
    }
  }

  // End emergency session in Firebase
  Future<void> _endEmergencySession() async {
    if (_currentEmergencySessionId == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('emergency_sessions')
          .doc(_currentEmergencySessionId!)
          .update({
        'isActive': false,
        'endTime': FieldValue.serverTimestamp(),
        'endedBy': 'user',
      });

      print("✅ Emergency session ended in Firebase");
      _currentEmergencySessionId = null;
      
    } catch (e) {
      print("❌ Error ending emergency session: $e");
    }
  }

  // Send message when location sharing is stopped
  Future<void> _sendLocationStoppedMessage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final contactsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('emergency_contacts')
          .get();

      final timeStr = DateTime.now().toString().substring(11, 16);
      
      final stoppedMessage = """
✅ EMERGENCY RESOLVED - ${timeStr}

I have manually stopped the emergency alert and LIVE location sharing.

🛑 The live location link is now INACTIVE and will no longer update.

I am now safe and no longer need assistance.

Thank you for your concern and quick response.

- Raksha Safety App
""";

      for (var contactDoc in contactsSnapshot.docs) {
        final contactData = contactDoc.data();
        final phoneNumber = contactData['phone'] as String?;
        
        if (phoneNumber != null && phoneNumber.isNotEmpty) {
          await _sendSMSMessage(phoneNumber, stoppedMessage);
        }
      }

      print("✅ Emergency resolved message sent to ${contactsSnapshot.docs.length} contacts");
      
    } catch (e) {
      print("❌ Error sending emergency resolved message: $e");
    }
  }

  // --- Copy Location Logic ---
  void _copyLocation() {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location not yet determined.")),
      );
      return;
    }
    
    final String mapsLink = 
        'http://maps.google.com/maps?q=${_currentPosition!.latitude},${_currentPosition!.longitude}';

    Clipboard.setData(ClipboardData(text: mapsLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Current location link copied to clipboard!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Current location point for the map and marker
    final LatLng initialPoint = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) 
        : const LatLng(28.7041, 77.1025);
    
    final bool shouldShowHomeContent = _currentIndex == 0;

    // REMOVED: Scaffold wrapper and bottomNavigationBar
    // HomeScreen will handle the navigation
    return shouldShowHomeContent
        ? _HomeMapContentView(
            triggerSos: _triggerSos, 
            stopActiveSos: _stopActiveSos,
            testAlert: _testAlert,
            testVoiceDetection: _testVoiceDetection,
            mapController: _mapController, 
            initialPoint: initialPoint, 
            lastUpdated: _lastUpdated, 
            isLocationActive: _currentPosition != null,
            copyLocation: _copyLocation,
            isSosActive: _isSosActive,
            isPreSosCounting: _isPreSosCounting,
            isVoiceSetUp: _isVoiceSetUp,
            emergencyContactCount: _emergencyContactCount,
          )
        : _tabs[_currentIndex]; // Show the other simple tab contents
  }
}

// --- NEW WIDGET FOR HOME CONTENT (Functional, accepts state via constructor) ---
class _HomeMapContentView extends StatelessWidget {
  final VoidCallback triggerSos;
  final VoidCallback stopActiveSos;
  final VoidCallback copyLocation;
  final VoidCallback testAlert;
  final VoidCallback testVoiceDetection;
  final MapController mapController;
  final LatLng initialPoint;
  final String lastUpdated;
  final bool isLocationActive;
  final bool isSosActive;
  final bool isPreSosCounting;
  final bool isVoiceSetUp;
  final int emergencyContactCount;

  static const Color purpleBackground = Color(0xFF6A5AE3); 

  const _HomeMapContentView({
    required this.triggerSos,
    required this.stopActiveSos,
    required this.copyLocation,
    required this.testAlert,
    required this.testVoiceDetection,
    required this.mapController,
    required this.initialPoint,
    required this.lastUpdated,
    required this.isLocationActive,
    required this.isSosActive,
    required this.isPreSosCounting,
    required this.isVoiceSetUp,
    required this.emergencyContactCount,
  });
  
  void _navigateTo(Widget screen, BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    
    const String gestureStatus = 'Ready';
    String voiceStatus = isVoiceSetUp ? 'Ready' : 'Not Set Up';
    // Show actual contact count
    String contactsStatus = '$emergencyContactCount/5 contacts';

    // Determine button state and text
    Color sosButtonColor = Colors.red[600]!;
    String sosButtonText = "TRIGGER SOS";
    VoidCallback sosButtonAction = triggerSos;
    IconData sosButtonIcon = Icons.gpp_bad;

    if (isPreSosCounting) {
      sosButtonColor = Colors.orange[600]!;
      sosButtonText = "CANCEL TRIGGER";
      sosButtonIcon = Icons.cancel;
      sosButtonAction = stopActiveSos;
    } else if (isSosActive) {
      sosButtonColor = Colors.green[600]!;
      sosButtonText = "STOP LOCATION SHARING";
      sosButtonIcon = Icons.location_off;
      sosButtonAction = stopActiveSos;
      sosButtonAction = () => _navigateTo(const SecureVaultScreen(), context); 
    }


    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Image.asset('assets/images/raksha_logo.png', width: 32, height: 32), 
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Raksha", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text("Silent Safety Companion", style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Location Sharing Status (only show when active)
          if (isSosActive) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[300]!, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_on, color: Colors.red[600], size: 24),
                      const SizedBox(width: 8),
                      Text(
                        "🚨 LIVE LOCATION SHARING ACTIVE",
                        style: TextStyle(
                          color: Colors.red[600],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your location is being sent to emergency contacts every 30 seconds",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red[700],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Only YOU can stop this by tapping the button below",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red[800],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 1. TRIGGER SOS Button (Dynamically changes state)
          MaterialButton(
            onPressed: sosButtonAction,
            color: sosButtonColor,
            minWidth: double.infinity,
            height: 80,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(sosButtonIcon, color: Colors.white, size: 32),
                const SizedBox(width: 10),
                Text(sosButtonText, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. LOCATION SERVICES Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              height: 250,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [Icon(Icons.location_on, size: 18, color: purpleBackground), SizedBox(width: 5), Text("Location Services", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                            Text("Last updated: $lastUpdated", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: isLocationActive ? Colors.green[100] : Colors.red[100], borderRadius: BorderRadius.circular(10)),
                          child: Text(isLocationActive ? "Active" : "Inactive", style: TextStyle(color: isLocationActive ? Colors.green[800] : Colors.red[800], fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  
                  // Map View (Flutter_Map)
                  Expanded(
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                          child: FlutterMap(
                            mapController: mapController,
                            options: MapOptions(
                              initialCenter: initialPoint,
                              initialZoom: 16.0,
                              minZoom: 2.0,
                              maxZoom: 18.0,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                              onTap: (tapPosition, latlng) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opening Full Screen Map...")));
                              },
                            ),
                            children: [
                              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.raksha.raksha'),
                              MarkerLayer(
                                markers: [
                                  Marker(point: initialPoint, width: 80, height: 80, child: const Icon(Icons.location_on, color: Colors.green, size: 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Copy Location Button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.copy, color: purpleBackground),
                            style: IconButton.styleFrom(backgroundColor: Colors.white.withAlpha(230), minimumSize: const Size(30, 30)),
                    
                            onPressed: copyLocation,
                            tooltip: 'Copy current location link',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 3. PROTECTION STATUS Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Protection Status", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatusItem(Icons.back_hand, "Gesture Mode", gestureStatus),
                      _buildStatusItem(Icons.mic, "Voice Mode", voiceStatus),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. QUICK SETUP Card (Links to Onboarding/Tabs)
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Quick Setup", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  _buildSetupRow(Icons.back_hand, "Train Gestures", "Customize emergency hand signals", () => _navigateTo(const OnboardingGestureScreen(), context)),
                  _buildSetupRow(Icons.mic, "Voice Triggers", isVoiceSetUp ? "Edit covert phrases" : "Set up covert phrases", () => _navigateTo(const OnboardingVoiceScreen(), context)), 
                  _buildSetupRow(Icons.contacts, "Emergency Contacts", contactsStatus, () => _navigateTo(const ContactsTab(), context)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 5. SAFETY TOOLS Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Safety Tools", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSafetyTool(Icons.notifications_active, "Test Alert", () { testAlert(); }, context),
                      _buildSafetyTool(Icons.mic, "Test Voice", () { testVoiceDetection(); }, context),
                      _buildSafetyTool(Icons.lock, "Secure Vault", () { _navigateTo(const SecureVaultScreen(), context); }, context),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Helper Widget for Protection Status Section
  Widget _buildStatusItem(IconData icon, String title, String status) {
    final bool isReady = status == 'Ready';
    return Column(
      children: [
        Icon(icon, size: 36, color: isReady ? Colors.green : Colors.orange),
        const SizedBox(height: 5),
        Text(title, style: const TextStyle(fontSize: 14)),
        Text(status, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isReady ? Colors.green : Colors.orange)),
      ],
    );
  }

  // Helper Widget for Quick Setup Section
  Widget _buildSetupRow(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: purpleBackground),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  // Helper Widget for Safety Tools Section
  Widget _buildSafetyTool(IconData icon, String title, VoidCallback onTap, BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, size: 48, color: purpleBackground),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}