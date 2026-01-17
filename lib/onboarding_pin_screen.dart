// lib/onboarding_pin_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// NEW IMPORTS for Security and Navigation
import 'package:raksha/onboarding_biometric_screen.dart'; 
import 'package:crypto/crypto.dart';
import 'dart:convert';

// Helper function to hash the PIN securely (Shared with SecureVaultScreen)
String hashPin(String pin) {
  final bytes = utf8.encode(pin); 
  final hash = sha256.convert(bytes); 
  return hash.toString();
}

class OnboardingPinScreen extends StatefulWidget {
  const OnboardingPinScreen({super.key});

  @override
  State<OnboardingPinScreen> createState() => _OnboardingPinScreenState();
}

class _OnboardingPinScreenState extends State<OnboardingPinScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;

  Future<void> _setPinAndContinue() async {
    final pin = _pinController.text;
    final confirmPin = _confirmPinController.text;

    // --- Validation ---
    if (pin.length != 4 || confirmPin.length != 4) {
      _showSnackBar("PIN must be exactly 4 digits.");
      return;
    }
    if (pin != confirmPin) {
      _showSnackBar("PINs do not match.");
      return;
    }
    // --- End Validation ---

    setState(() => _isLoading = true);

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      
      // CRITICAL: HASH THE PIN BEFORE STORING IT
      final pinHash = hashPin(pin);

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'secureVaultPinHash': pinHash, // Store the secure HASH
        'onboardingStep': 'pin_complete',
      });

      _showSnackBar("Secure Vault PIN Set!");

      // CRITICAL FIX: Navigate to the mandatory Biometric Setup Screen
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingBiometricScreen()),
          (route) => false); 

    } catch (e) {
      _showSnackBar("Failed to save PIN. Try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // UI remains the same
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF936EE4), Color(0xFF6A5AE3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Secure Vault Setup",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "This is the **4-digit** PIN you'll require to access the Secure Vault containing your emergency recordings.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 48),

                    // PIN Input
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4, 
                      textAlign: TextAlign.center,
                      obscureText: true,
                      decoration: _buildInputDecoration("4-Digit PIN"),
                    ),
                    const SizedBox(height: 16),

                    // Confirm PIN Input
                    TextField(
                      controller: _confirmPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4, 
                      textAlign: TextAlign.center,
                      obscureText: true,
                      decoration: _buildInputDecoration("Confirm PIN"),
                    ),
                    const SizedBox(height: 48),

                    // Set PIN Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _setPinAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF6A5AE3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Set PIN & Continue",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Loading Indicator
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      counterText: "", 
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
    );
  }
}