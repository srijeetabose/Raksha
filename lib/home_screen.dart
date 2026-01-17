// lib/home_screen.dart
// This file acts as the main Router/Wrapper for the Home Dashboard.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Import the specific dashboard implementations
import 'package:raksha/user_safety_dashboard.dart'; // The core user home screen
import 'package:raksha/gestures_tab.dart';
import 'package:raksha/contacts_tab.dart';
import 'package:raksha/settings_tab.dart';
// Note: PoliceAlertsDashboard and PolicePendingScreen are defined below.

// Defines the two primary modes of operation
enum AppMode { user, police }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State to determine what the user is currently viewing
  AppMode _currentMode = AppMode.user;
  bool _isPoliceVerified = false;
  bool _isLoading = true;
  int _currentTabIndex = 0; // For user mode navigation

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _startBackgroundServices();
  }
  
  // Start background services automatically
  Future<void> _startBackgroundServices() async {
    // Add delay to ensure app is fully initialized
    await Future.delayed(const Duration(seconds: 2));
    
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      
      // Start background service with user's configured gestures and voice triggers
      await platform.invokeMethod('startRealBackgroundService', {
        'gestures': ['Thumb_Up', 'Victory', 'Closed_Fist'], // Default gestures
        'crossApp': true,
      });
      
      print("✅ Background gesture service started");
      
      // Add small delay between service calls
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Start voice detection with user's triggers
      await platform.invokeMethod('startVoiceDetection', {
        'triggers': ['help me', 'emergency', 'call police'], // Will be loaded from Firebase
      });
      
      print("✅ Voice detection started");
      print("✅ All background services started automatically");
    } catch (e) {
      print("❌ Error starting background services: $e");
      // Don't crash the app if background services fail
    }
  }

  // --- Initialization Logic (Checks role only once on load) ---

  Future<void> _checkUserRole() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final verificationDoc = await _firestore.collection('police_verification').doc(userId).get();

      if (verificationDoc.exists) {
        final status = verificationDoc.data()?['verificationStatus'] as String?;
        if (status == 'approved') {
          // If approved, set the verification flag and start in Police Mode view
          _isPoliceVerified = true;
          _currentMode = AppMode.police; // Default to Police mode for verified officers
        }
      }
    } catch (e) {
      print("Error checking police role: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // --- Dashboard Builder ---

  // Determines which content widget to display (Police Alerts or User Safety)
  Widget _buildCurrentDashboard() {
    if (_isPoliceVerified && _currentMode == AppMode.police) {
      // Verified Police Officer View: Show Alerts Dashboard
      return const PoliceAlertsDashboard();
    }
    
    // User Mode: Show different tabs based on current index
    switch (_currentTabIndex) {
      case 0:
        return const UserSafetyDashboard();
      case 1:
        return const GesturesTab();
      case 2:
        return const ContactsTab();
      case 3:
        return const SettingsTab();
      default:
        return const UserSafetyDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6A5AE3))),
      );
    }
    
    // CRITICAL CHECK: Show Pending Screen if status is NOT approved, but police document exists
    if (_isPoliceVerified) {
      final userId = _auth.currentUser!.uid;
      return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('police_verification').doc(userId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6A5AE3))));
          }
          // If status is still pending, block access
          if (snapshot.hasData && snapshot.data!['verificationStatus'] == 'pending') {
            return const PolicePendingScreen();
          }
          // If approved (or rejected/other), proceed to main scaffold (but rejected goes to User mode via _checkUserRole)
          return _buildScaffold(context);
        },
      );
    }

    return _buildScaffold(context);
  }

  // --- Main Scaffold Structure ---
  
  Widget _buildScaffold(BuildContext context) {
    // Color variables for consistency
    const Color purpleDark = Color(0xFF6A5AE3);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Raksha", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
        backgroundColor: purpleDark,
        elevation: 0,
        // Actions on the AppBar
        actions: [
          // 1. DUAL ROLE MODE TOGGLE (Only visible to verified police officers)
          if (_isPoliceVerified)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  _currentMode = _currentMode == AppMode.user ? AppMode.police : AppMode.user;
                });
              },
              icon: Icon(_currentMode == AppMode.user ? Icons.security : Icons.person),
              label: Text(_currentMode == AppMode.user ? "POLICE MODE" : "USER MODE"),
            ),
          
          // 2. LOGOUT BUTTON (Always visible)
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _auth.signOut(), // AuthWrapper handles navigation back to login
          )
        ],
      ),
      body: _buildCurrentDashboard(),
      
      // 3. User Bottom Navigation Bar (Only for User Mode)
      bottomNavigationBar: _currentMode == AppMode.user 
        ? BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.back_hand), label: 'Gestures'),
              BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'Contacts'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            ],
            selectedItemColor: purpleDark,
            unselectedItemColor: Colors.grey,
            currentIndex: _currentTabIndex,
            onTap: (index) { 
              setState(() {
                _currentTabIndex = index;
              });
            },
          )
        : null,
    );
  }
}

// =========================================================================
// --- Dashboard Implementations (Needed here for the router to work) ---
// =========================================================================

// Screen shown to police users awaiting approval (Same as previous step)
class PolicePendingScreen extends StatelessWidget {
  const PolicePendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_clock, size: 64, color: Colors.amber),
              SizedBox(height: 20),
              Text(
                "Verification Pending",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                "Your account is under manual review. You will receive an update once your verification status is 'approved' or 'rejected'.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Destination for Verified Police (Alerts and Active/Inactive toggle)
class PoliceAlertsDashboard extends StatefulWidget {
  const PoliceAlertsDashboard({super.key});

  @override
  State<PoliceAlertsDashboard> createState() => _PoliceAlertsDashboardState();
}

class _PoliceAlertsDashboardState extends State<PoliceAlertsDashboard> {
  // Status to receive alerts (isPoliceActive field in Firestore)
  bool _isPoliceActive = false; 
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadPoliceStatus();
  }

  // Loads the Police Active status from Firestore
  Future<void> _loadPoliceStatus() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (userDoc.exists) {
      setState(() {
        // Reads the 'isPoliceActive' field (defaults to false)
        _isPoliceActive = userDoc.data()?['isPoliceActive'] ?? false; 
      });
    }
  }

  // Toggles Active/Inactive status and updates Firestore
  Future<void> _togglePoliceStatus(bool newValue) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _isPoliceActive = newValue;
    });

    try {
      await _firestore.collection('users').doc(userId).update({
        'isPoliceActive': newValue,
        'lastStatusChange': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Status updated to: ${newValue ? 'Active' : 'Inactive'}")),
        );
      }
      // TODO: Start/Stop background location service here
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update status.")),
        );
      }
      // Revert UI on error
      setState(() {
        _isPoliceActive = !newValue;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Placeholder for the main Police Dashboard UI
    return Column(
      children: [
        // Active/Inactive Toggle UI
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Availability Status:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Switch(
                value: _isPoliceActive,
                onChanged: _togglePoliceStatus,
                activeThumbColor: Colors.green,
                inactiveThumbColor: Colors.red,
              ),
            ],
          ),
        ),
        
        // Alert List/Map View (Placeholder)
        Expanded(
          child: Center(
            child: Text(
              _isPoliceActive 
                ? "Live Alert Feed (20km Radius)\n(SOS alerts display here)"
                : "Go Active to receive alerts within 20km.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}