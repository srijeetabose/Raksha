// lib/onboarding_biometric_screen.dart

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:raksha/home_screen.dart'; 

class OnboardingBiometricScreen extends StatefulWidget {
  const OnboardingBiometricScreen({super.key});

  @override
  State<OnboardingBiometricScreen> createState() => _OnboardingBiometricScreenState();
}

class _OnboardingBiometricScreenState extends State<OnboardingBiometricScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _canCheckBiometrics = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  // Check if the device supports biometrics
  Future<void> _checkBiometrics() async {
    try {
      final bool canCheck = await _localAuth.canCheckBiometrics;
      if (mounted) {
        setState(() {
          _canCheckBiometrics = canCheck;
        });
      }
    } catch (e) {
      // Avoid print in production
      if (mounted) setState(() => _canCheckBiometrics = false);
    }
  }

  // Attempt to enroll the user's biometrics
  Future<void> _enrollBiometrics() async {
    if (!_canCheckBiometrics) {
      _showSnackBar("Biometrics not available. Skipping setup.");
      _finalizeAndNavigate(); // If unavailable, skip and go home
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      // First check if biometrics are enrolled on device
      final List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();
      
      if (availableBiometrics.isEmpty) {
        _showSnackBar("No biometrics enrolled on device. Please set up fingerprint/face ID in device settings first.");
        _finalizeAndNavigate();
        return;
      }
      
      // debug removed
      
      // Try biometric-only first, then fallback to device credentials
      bool didAuthenticate = false;
      
      try {
        didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'Touch your fingerprint sensor or look at the camera to set up biometric recovery for Secure Vault.',
          options: const AuthenticationOptions(
            stickyAuth: true,
            useErrorDialogs: true,
            biometricOnly: true, // Only use biometrics, not device PIN
          ),
        );
      } catch (biometricError) {
        // debug removed
        
        // Fallback to device credentials (PIN/Pattern/Password)
        try {
          didAuthenticate = await _localAuth.authenticate(
            localizedReason: 'Use your device PIN, pattern, or password to set up biometric recovery for Secure Vault.',
            options: const AuthenticationOptions(
              stickyAuth: true,
              useErrorDialogs: true,
              biometricOnly: false, // Allow device PIN/Pattern/Password
            ),
          );
        } catch (fallbackError) {
          // debug removed
          throw fallbackError; // Re-throw to be handled by outer catch
        }
      }

      if (didAuthenticate) {
        // Success: Save flag and navigate
        _showSnackBar("Biometrics set successfully! Proceeding to Home.");
        await _saveBiometricFlag();
        _finalizeAndNavigate(); 
      } else {
        _showSnackBar("Biometric authentication cancelled. You can set this up later in Settings.");
        _finalizeAndNavigate();
      }
    } catch (e) {
      // debug removed
      // Handle the use_build_context_synchronously warning by checking mounted
      if (mounted) {
        String errorMessage = "Biometric setup failed. You can set this up later in Settings.";
        
        // More comprehensive error handling
        String errorStr = e.toString().toLowerCase();
        if (errorStr.contains('no_fragment_activity') || errorStr.contains('fragmentactivity')) {
          errorMessage = "Biometric setup requires app restart. Please restart the app and try again.";
        } else if (errorStr.contains('notavailable') || errorStr.contains('not available')) {
          errorMessage = "Biometrics not available on this device.";
        } else if (errorStr.contains('notenrolled') || errorStr.contains('not enrolled')) {
          errorMessage = "No fingerprints enrolled. Please set up fingerprint in device settings first.";
        } else if (errorStr.contains('usercanceled') || errorStr.contains('user canceled')) {
          errorMessage = "Biometric authentication was cancelled.";
        } else if (errorStr.contains('lockedout') || errorStr.contains('locked out')) {
          errorMessage = "Too many failed attempts. Please try again later.";
        } else if (errorStr.contains('permanentlylocked') || errorStr.contains('permanently locked')) {
          errorMessage = "Biometric authentication is permanently locked. Please use device PIN.";
        } else if (errorStr.contains('timeout')) {
          errorMessage = "Biometric authentication timed out. Please try again.";
        } else if (errorStr.contains('processingfailed') || errorStr.contains('processing failed')) {
          errorMessage = "Biometric processing failed. Please try again.";
        }
        
        _showSnackBar(errorMessage);
        _finalizeAndNavigate(); // Allow user to proceed after error
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  // Save biometric flag to Firestore
  Future<void> _saveBiometricFlag() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'biometricEnabled': true,
        });
      }
    } catch (e) {
      // debug removed
    }
  }
  
  // --- CRITICAL FINALIZATION LOGIC ---
  Future<void> _finalizeAndNavigate() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    try {
      // Set the final onboarding flag to TRUE
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'onboardingComplete': true, 
        'onboardingStep': 'complete',
        // TODO: Save biometricEnabled: true if the enrollment in _enrollBiometrics succeeded 
      });
    } catch (e) {
      // Avoid print in production
    }

    // Navigate directly to home screen after biometrics
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _showSnackBar(String message) {
    // FIX: Guard with mounted check to resolve 'use_build_context_synchronously' warning
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

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
      appBar: AppBar(title: const Text("Step 1b: Biometric Recovery")),
      body: Container(
        decoration: gradient,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fingerprint, size: 80, color: _canCheckBiometrics ? Colors.white : Colors.redAccent),
                const SizedBox(height: 20),
                const Text("Set Up Fingerprint/Face ID", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text(
                  _canCheckBiometrics
                      ? "This biometric data will be used as a **one-time recovery** to verify your identity before resetting your Secure Vault PIN."
                      : "Biometric hardware not found or not set up on device. You will use Email OTP for recovery.",
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                
                // Enroll Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _enrollBiometrics,
                    style: ElevatedButton.styleFrom(backgroundColor: _canCheckBiometrics ? Colors.white : Colors.grey, foregroundColor: const Color(0xFF6A5AE3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Color(0xFF6A5AE3))
                        : Text(_canCheckBiometrics ? "Enable Biometrics" : "Continue Anyway", style: const TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 16),
                // Skip Button for non-critical flow
                if (_canCheckBiometrics)
                  TextButton(
                    onPressed: _finalizeAndNavigate,
                    child: const Text("Skip for now (Recovery limited to Email)", style: TextStyle(color: Colors.white70)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}