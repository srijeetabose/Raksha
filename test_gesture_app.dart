// MINIMAL GESTURE DETECTION TEST
// This will prove MediaPipe works without camera conflicts

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(TestGestureApp());

class TestGestureApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raksha Gesture Test',
      home: GestureTestScreen(),
    );
  }
}

class GestureTestScreen extends StatefulWidget {
  @override
  _GestureTestScreenState createState() => _GestureTestScreenState();
}

class _GestureTestScreenState extends State<GestureTestScreen> {
  String _gestureResult = "No gesture detected";
  bool _isDetecting = false;
  
  @override
  void initState() {
    super.initState();
    _startGestureDetection();
  }
  
  void _startGestureDetection() {
    // Test MediaPipe without camera conflicts
    Timer.periodic(Duration(seconds: 2), (timer) {
      _testGestureDetection();
    });
  }
  
  Future<void> _testGestureDetection() async {
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      final result = await platform.invokeMethod('testSimpleGestureDetection');
      
      if (result != null && mounted) {
        final gesture = result['gesture'] as String?;
        final confidence = result['confidence'] as double?;
        
        if (gesture != null && confidence != null) {
          setState(() {
            _gestureResult = "$gesture (${(confidence * 100).toInt()}%)";
            _isDetecting = true;
          });
          
          // Reset after 1 second
          Future.delayed(Duration(seconds: 1), () {
            if (mounted) {
              setState(() {
                _isDetecting = false;
                _gestureResult = "Waiting for next test...";
              });
            }
          });
        }
      }
    } catch (e) {
      print("Error testing gesture: $e");
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Raksha Gesture Test'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isDetecting ? Colors.green : Colors.grey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _isDetecting ? "🎯 GESTURE DETECTED!" : "👁️ TESTING...",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              _gestureResult,
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 40),
            Text(
              "This tests MediaPipe gesture detection\nwithout camera conflicts",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}