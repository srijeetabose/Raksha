// lib/onboarding_gesture_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:raksha/home_screen.dart';
import 'dart:async'; 

class OnboardingGestureScreen extends StatefulWidget {
  const OnboardingGestureScreen({super.key});

  @override
  State<OnboardingGestureScreen> createState() => _OnboardingGestureScreenState();
}

class _OnboardingGestureScreenState extends State<OnboardingGestureScreen> {
  // Available Gestures (Matching TFLite labels for selection)
  final List<Map<String, dynamic>> availableGestures = [
    {'name': 'Thumbs Up', 'icon': Icons.thumb_up, 'key': 'Thumb_Up', 'selected': false, 'emoji': '👍'},
    {'name': 'Thumbs Down', 'icon': Icons.thumb_down, 'key': 'Thumb_Down', 'selected': false, 'emoji': '👎'},
    {'name': 'Peace Sign', 'icon': Icons.pan_tool, 'key': 'Victory', 'selected': false, 'emoji': '✌️'},
    {'name': 'Closed Fist', 'icon': Icons.back_hand, 'key': 'Closed_Fist', 'selected': false, 'emoji': '✊'},
  ];
  
  List<String> _selectedKeys = [];
  bool _isLoading = false;
  
  // Camera variables
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  
  // Gesture detection feedback
  String _currentGesture = "No gesture detected";
  double _confidence = 0.0;
  bool _isDetecting = false;
  Timer? _gestureTimer;
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadUserGestures();
    _initializeCamera();
  }

  @override
  void dispose() {
    _gestureTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  // Initialize camera
  Future<void> _initializeCamera() async {
    try {
      print("🎥 Initializing camera for onboarding...");
      _cameras = await availableCameras();
      print("📱 Found ${_cameras?.length} cameras");
      
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Use front camera for gesture detection
        final frontCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );
        
        print("📷 Using camera: ${frontCamera.name}");
        
        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        
        print("🔄 Initializing camera controller...");
        await _cameraController!.initialize();
        print("✅ Camera initialized successfully!");
        
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
          // Start gesture detection simulation for demo
          _startGestureDetectionDemo();
        }
      } else {
        print("❌ No cameras available");
      }
    } catch (e) {
      print('❌ Error initializing camera: $e');
      // Try to reinitialize after delay
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _initializeCamera();
        });
      }
    }
  }

  // Start gesture detection demo for onboarding
  void _startGestureDetectionDemo() {
    print("🎯 Starting REAL MediaPipe gesture detection...");
    
    // Initialize MediaPipe gesture recognition
    _initializeMediaPipeGestures();
    
    // Start real-time gesture detection
    _gestureTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        // Process current camera frame through MediaPipe
        await _processCurrentFrame();
      } catch (e) {
        print("❌ Error processing gesture frame: $e");
      }
    });
  }

  // Initialize MediaPipe gesture recognition
  Future<void> _initializeMediaPipeGestures() async {
    try {
      final platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('initializeGestureRecognition');
      print("✅ MediaPipe gesture recognition initialized");
    } catch (e) {
      print("❌ Failed to initialize MediaPipe: $e");
    }
  }

  // Process current camera frame for gesture detection
  Future<void> _processCurrentFrame() async {
    try {
      final platform = MethodChannel('com.example.raksha/gesture_service');
      final result = await platform.invokeMethod('processFrame');
      
      if (result != null && result['gesture'] != null) {
        final gesture = result['gesture'] as String;
        final confidence = (result['confidence'] as double?) ?? 0.0;
        
        setState(() {
          _currentGesture = gesture;
          _confidence = confidence;
          _isDetecting = confidence > 0.5;
        });
        
        print("🎯 REAL MediaPipe detection: $gesture (${(confidence * 100).toInt()}%)");
      } else {
        setState(() {
          _currentGesture = 'No gesture detected';
          _confidence = 0.0;
          _isDetecting = false;
        });
      }
    } catch (e) {
      print("❌ Error processing frame: $e");
    }
  }

  // Fetch the currently saved gestures from Firestore
  Future<void> _loadUserGestures() async {
    if (_userId == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
      if (doc.exists && doc.data() != null && doc.data()!['triggerGestures'] is List) {
        final List<String> savedKeys = List<String>.from(doc.data()!['triggerGestures']);
        
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

  // Toggle selection logic (Max 2)
  void _toggleSelection(int index) {
    if (_isLoading) return;

    String key = availableGestures[index]['key'];
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
        availableGestures[index]['selected'] = false;
      } else if (_selectedKeys.length < 2) {
        _selectedKeys.add(key);
        availableGestures[index]['selected'] = true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Maximum of 2 gestures allowed.")),
        );
      }
    });
  }

  // Save the selected gestures to Firestore and navigate
  Future<void> _saveGesturesAndContinue() async {
    if (_selectedKeys.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must select exactly two (2) gestures to continue.")),
      );
      return;
    }
    if (_userId == null) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).update({
        'triggerGestures': _selectedKeys,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Emergency gestures saved successfully! Proceeding.")),
      );
      
      // Navigate to the main Home Screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to save gestures. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color purpleDark = Color(0xFF6A5AE3);

    return Scaffold(
      appBar: AppBar(title: const Text("Setup: Silent Gestures")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FRONT CAMERA PREVIEW (Fixed aspect ratio)
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      _isCameraInitialized && _cameraController != null
                          ? SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController!.value.previewSize!.height,
                                  height: _cameraController!.value.previewSize!.width,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Colors.white),
                                  SizedBox(height: 10),
                                  Text("Initializing Camera...", style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                      // Gesture Detection Overlay
                      if (_isCameraInitialized)
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _isDetecting ? Colors.green.withOpacity(0.8) : Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _isDetecting ? "🎯 DETECTING" : "👁️ MONITORING",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _currentGesture,
                                  style: TextStyle(
                                    color: _isDetecting ? Colors.yellow : Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                if (_confidence > 0)
                                  Text(
                                    "Confidence: ${(_confidence * 100).toStringAsFixed(0)}%",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 25),

              // CHOOSE GESTURES Section
              const Text("Choose Emergency Gestures", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("Select exactly 2 gestures. The AI model is pre-trained for all gestures.", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),

              // Gesture Grid (4 buttons)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12.0,
                  mainAxisSpacing: 12.0,
                  childAspectRatio: 2.2, // Increased to prevent overflow
                ),
                itemCount: availableGestures.length,
                itemBuilder: (context, index) {
                  final gesture = availableGestures[index];
                  final isSelected = gesture['selected'] as bool;
                  return InkWell(
                    onTap: _isLoading ? null : () => _toggleSelection(index),
                    child: Card(
                      color: isSelected ? purpleDark : Colors.white,
                      elevation: isSelected ? 8 : 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(gesture['emoji'] as String, style: const TextStyle(fontSize: 28)), 
                          const SizedBox(height: 2),
                          Flexible(
                            child: Text(
                              gesture['name'] as String, 
                              style: TextStyle(
                                fontSize: 12, 
                                fontWeight: FontWeight.bold, 
                                color: isSelected ? Colors.white : Colors.black
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected) const Text("✓ Selected", style: TextStyle(color: Colors.white70, fontSize: 9)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Center(child: Text("Selected: ${_selectedKeys.length}/2 gestures", style: TextStyle(color: _selectedKeys.length == 2 ? Colors.green : Colors.orange))),
              const SizedBox(height: 30),

              // ACTIVATE Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveGesturesAndContinue,
                  icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Icon(Icons.play_arrow),
                  label: Text(_isLoading ? "SAVING..." : "Activate Emergency Gestures", style: const TextStyle(fontSize: 20)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // AI ENHANCED DETECTION Section
              const Text("AI Enhanced Detection", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFeatureItem("Works in low light conditions"),
                  _buildFeatureItem("Detects partial or stressed gestures"),
                  _buildFeatureItem("Real-time background monitoring"),
                  _buildFeatureItem("Front camera detection only"),
                  _buildFeatureItem("No training required - AI pre-trained"),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}