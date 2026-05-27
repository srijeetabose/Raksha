// lib/permissions_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:raksha/home_screen.dart';
// FIX 1: Import the correct next screen
import 'package:raksha/onboarding_pin_screen.dart'; // Correct destination for regular user

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _isLoading = false;

  final List<Permission> _requiredPermissions = [
    Permission.camera,
    Permission.microphone,
    Permission.speech, // For voice recognition
    Permission.locationAlways, // CRITICAL: Always allow location for emergency
    Permission.contacts,
    Permission.sms,
    Permission.notification,
    Permission.systemAlertWindow, // For overlay detection across apps
  ];

  Future<bool> _hasPermanentlyDenied() async {
    for (var permission in _requiredPermissions) {
      // Use isDenied to include permanent denial cases for the dialog logic
      if (await permission.isPermanentlyDenied) { 
        return true;
      }
    }
    return false;
  }

  // Show explanation for background permissions
  Future<void> _showBackgroundPermissionExplanation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            ' Emergency System Permissions',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For Raksha to work as a REAL emergency system, it needs:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 16),
                Text('� Camera: "While using the app" (Required)'),
                Text('• We\'ll use foreground service to stay active'),
                Text('• Emergency system runs continuously'),
                SizedBox(height: 8),
                Text(' Microphone: "While using the app" (Required)'),
                Text('• Background service keeps microphone active'),
                SizedBox(height: 8),
                Text(' Location: "Allow all the time"'),
                Text('• Send your location in emergencies'),
                Text('• Work even when phone is locked'),
                SizedBox(height: 16),
                Text(
                  ' IMPORTANT: For Location, choose "Allow all the time". For Camera/Microphone, "While using the app" is fine - our background service will handle it!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('I Understand - Grant Permissions'),
            ),
          ],
        );
      },
    );
  }

  // DISABLED: Background camera permission causes hanging
  Future<void> _requestBackgroundCameraPermission() async {
    // debug removed
    // This was causing the infinite loading - skip it for now
    return;
  }

  // --- Core Permission Request Logic ---
  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    try {
      // debug removed
      
      // 1. Request basic permissions with timeout to prevent hanging
      Map<Permission, PermissionStatus> statuses = {};
      
      try {
        statuses = await _requiredPermissions.request().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            // debug removed
            return <Permission, PermissionStatus>{};
          },
        );
      } catch (e) {
        // debug removed
      }

      // Debug: Print permission statuses
      // debug removed
      for (var entry in statuses.entries) {
        // debug removed
      }

      // 2. Show special permission info (don't wait for them)
      _showSpecialPermissionInfo();

      // 3. Navigate immediately to avoid hanging
      // debug removed
      _navigateToNextStep();
      
    } catch (e) {
      // debug removed
      // Even if there's an error, go to home screen
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()), 
          (route) => false);
    }
    
    setState(() => _isLoading = false);
  }

  // Show info about special permissions (non-blocking)
  void _showSpecialPermissionInfo() {
    // debug removed
    // Don't show blocking dialogs - just log that user can enable these later
    // The app will work without these initially
  }

  // Show dialog for overlay permission
  Future<void> _showOverlayPermissionDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(" Enable Display Over Apps"),
        content: const Text(
          " CRITICAL: Enable Display Over Other Apps\n\n"
          "Steps to follow:\n"
          "1. Tap 'Open Settings' below\n"
          "2. Find 'Raksha' in the app list\n"
          "3. Toggle ON 'Display over other apps'\n"
          "4. Press back button to return here\n\n"
          " Without this, gestures won't work when using other apps!"
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openOverlaySettings();
            },
            child: const Text("Open Settings"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Skip for now"),
          ),
        ],
      ),
    );
  }

  // Show dialog for accessibility permission
  Future<void> _showAccessibilityPermissionDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("♿ Enable Accessibility Service"),
        content: const Text(
          "♿ CRITICAL: Enable Accessibility Service\n\n"
          "Steps to follow:\n"
          "1. Tap 'Open Settings' below\n"
          "2. Find 'Raksha' in Accessibility list\n"
          "3. Toggle ON the Raksha service\n"
          "4. Confirm 'OK' on the warning dialog\n"
          "5. Press back button to return here\n\n"
          " Without this, emergency detection won't work when screen is locked!"
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Open accessibility settings
              _openAccessibilitySettings();
            },
            child: const Text("Open Settings"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Skip for now"),
          ),
        ],
      ),
    );
  }

  // Open accessibility settings
  void _openAccessibilitySettings() async {
    try {
      const platform = MethodChannel('com.example.raksha/permissions');
      await platform.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      // debug removed
    }
  }

  // Open overlay settings
  void _openOverlaySettings() async {
    try {
      const platform = MethodChannel('com.example.raksha/permissions');
      await platform.invokeMethod('openOverlaySettings');
    } catch (e) {
      // debug removed
    }
  }

  // Navigate to next onboarding step
  void _navigateToNextStep() async {
    // debug removed
    
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      // debug removed
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      final String? role = doc.data()?['userRole'] as String?;
      // debug removed

      if (mounted) {
        if (role == 'police') {
          // debug removed
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
        } else {
          // debug removed
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const OnboardingPinScreen()), 
              (route) => false);
        }
      }
    } catch (error) {
      // debug removed
      // Default to PIN setup for regular users
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OnboardingPinScreen()), 
            (route) => false);
      }
    }
  }

  // --- Navigation Logic ---
  void _navigateBasedOnRole() async {
    // debug removed
    
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      // debug removed
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
      }
      return;
    }

    try {
      // debug removed
      
      // Update onboarding completion status FIRST
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'onboardingComplete': true,
        'onboardingStep': 'completed',
        'permissionsGranted': true,
      });
      
      // debug removed

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      final String? role = doc.data()?['userRole'] as String?;
      // debug removed

      if (mounted) {
        if (role == 'police') {
          // debug removed
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
        } else {
          // debug removed
          // debug removed
          
          // Check if PIN is already set
          final pinHash = doc.data()?['secureVaultPinHash'] as String?;
          if (pinHash != null) {
            // debug removed
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
          } else {
            // debug removed
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const OnboardingPinScreen()), 
                (route) => false);
          }
        }
      }
    } catch (error) {
      // debug removed
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- Dialogs ---

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Permissions Required"),
          content: const Text(
              "Raksha needs Camera, Microphone, Location, Contacts, and SMS permissions to function as a silent safety companion. Please grant all permissions."),
          actions: <Widget>[
            TextButton(
              child: const Text("Grant Permissions"),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                _requestPermissions(); // Re-run the request
              },
            ),
          ],
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Permission Denied Permanently"),
          content: const Text(
              "It looks like you permanently denied some permissions. You must manually enable them in App Settings to proceed."),
          actions: <Widget>[
            TextButton(
              child: const Text("Open Settings"),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                openAppSettings(); // Open phone's app settings
                setState(() => _isLoading = false);
              },
            ),
          ],
        );
      },
    );
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    const gradient = BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF936EE4), Color(0xFF6A5AE3)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );

    return Scaffold(
      body: Container(
        decoration: gradient,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 48),

                  // Title and Subtitle with requested privacy text
                  const Text(
                    "App Permissions Required",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "We respect your privacy. Grant these permissions for the app to work and protect you in emergencies.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Permission Card List
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10)
                        ],
                      ),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _buildPermissionItem(Icons.camera_alt, "Camera", "For silent gesture recognition & emergency recording"),
                          _buildPermissionItem(Icons.mic, "Microphone", "For voice triggers & silent audio recording"),
                          _buildPermissionItem(Icons.location_on, "Location (Always)", "To send your live location to emergency contacts"),
                          _buildPermissionItem(Icons.contact_phone, "Contacts", "To access your emergency contacts and send SMS"),
                          _buildPermissionItem(Icons.storage, "Storage/Media", "To save recordings and upload Police IDs"),
                          _buildPermissionItem(Icons.sms, "SMS", "To send immediate alerts without needing the internet"),
                          _buildPermissionItem(Icons.notifications, "Notifications", "To keep the silent SOS service running in the background"),
                          _buildPermissionItem(Icons.layers, "Display Over Apps", " MANUAL SETUP: We'll guide you to enable this in Settings for cross-app detection"),
                          _buildPermissionItem(Icons.accessibility, "Accessibility Service", " MANUAL SETUP: We'll guide you to enable this in Settings > Accessibility for system-wide detection"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Allow Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _requestPermissions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA995E9),
                        foregroundColor: const Color(0xFF3D2C8D),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Allow All Permissions",
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Continue Button (bypasses hanging permission requests)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        // debug removed
                        setState(() => _isLoading = false);
                        _navigateToNextStep();
                      },
                      child: const Text(
                        "Continue to App",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF6A5AE3), size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF555555)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}