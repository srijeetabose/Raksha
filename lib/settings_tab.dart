// lib/settings_tab.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:raksha/app_guidelines_screen.dart'; // New file for guidelines
import 'package:raksha/sos_service_channel.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final TextEditingController _voiceTriggerController = TextEditingController();

  // State for Toggles
  bool _isGestureDetectionEnabled = false;
  bool _isVoiceDetectionEnabled = false;
  bool _isLiveLocationEnabled = false;
  bool _isBackgroundRunningEnabled = false;
  
  // State for Voice Trigger
  String _currentTriggerWord = "Loading...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  @override
  void dispose() {
    _voiceTriggerController.dispose();
    super.dispose();
  }

  // --- Data Loading and Saving ---

  Future<void> _loadSettings() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _isGestureDetectionEnabled = data['isGestureDetectionEnabled'] ?? false;
            _isVoiceDetectionEnabled = data['isVoiceDetectionEnabled'] ?? false;
            _isLiveLocationEnabled = data['isLiveLocationEnabled'] ?? false;
            _isBackgroundRunningEnabled = data['isBackgroundRunningEnabled'] ?? true; // Assume true if not set
            _currentTriggerWord = data['voiceTriggerWord'] ?? "Strawberry";
            _voiceTriggerController.text = _currentTriggerWord;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore.collection('users').doc(userId).update({key: value});
      
      // Restart background service with new settings
      if (key.contains('Detection') || key == 'isBackgroundRunningEnabled') {
        await _restartBackgroundService();
      }
      
      _showSnackBar("Setting updated.");
    } catch (e) {
      _showSnackBar("Failed to save setting.", Colors.red);
      // Reload settings on failure to revert the UI switch
      _loadSettings(); 
    }
  }

  Future<void> _restartBackgroundService() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final doc = await _firestore.collection('users').doc(userId).get();
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
        }
      }
    } catch (e) {
      print('Failed to restart background service: $e');
    }
  }

  Future<void> _testLocationServices() async {
    setState(() => _isLoading = true);
    try {
      // Force restart the background service to test location
      await _restartBackgroundService();
      _showSnackBar("Location services test initiated. Check notification bar.", Colors.blue);
    } catch (e) {
      _showSnackBar("Location test failed: ${e.toString()}", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testVoiceRecognition() async {
    setState(() => _isLoading = true);
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final voiceWords = (data['triggerVoiceWords'] as List<dynamic>?)?.cast<String>() ?? [];
        
        if (voiceWords.isEmpty) {
          _showSnackBar("No voice triggers set up. Please configure voice triggers first.", Colors.orange);
        } else {
          await _restartBackgroundService();
          _showSnackBar("Voice recognition test started. Try saying 'Raksha ${voiceWords.first}'", Colors.blue);
        }
      }
    } catch (e) {
      _showSnackBar("Voice test failed: ${e.toString()}", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetOnboarding() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    setState(() => _isLoading = true);
    try {
      await _firestore.collection('users').doc(userId).update({
        'onboardingComplete': false,
        'onboardingStep': 'permissions',
      });
      _showSnackBar("Onboarding reset. Please restart the app to test permissions flow.", Colors.orange);
    } catch (e) {
      _showSnackBar("Failed to reset onboarding: ${e.toString()}", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // --- Voice Trigger Logic ---
  Future<void> _updateTriggerWord() async {
    final newWord = _voiceTriggerController.text.trim();
    if (newWord.isEmpty || newWord == _currentTriggerWord) {
      _showSnackBar("Trigger word unchanged.", Colors.orange);
      return;
    }
    
    setState(() => _isLoading = true);
    await _updateSetting('voiceTriggerWord', newWord);
    await _restartBackgroundService(); // Restart service with new trigger word
    setState(() {
      _currentTriggerWord = newWord;
      _isLoading = false;
    });
  }

  // --- Core Security Feature: Forgot PIN Logic (Same as before) ---
  Future<void> _forgotPinFlow() async {
    final userEmail = _auth.currentUser?.email;
    if (userEmail == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // 1. Initial Biometric Verification (If available)
      final bool canAuthenticate = await _localAuth.canCheckBiometrics;
      if (canAuthenticate) {
        final bool didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'Verify identity to reset Secure Vault PIN.',
          options: const AuthenticationOptions(
            biometricOnly: true,
            useErrorDialogs: true,
            stickyAuth: true,
          )
        );
        if (!didAuthenticate) {
          _showSnackBar("Biometric verification failed. Using Email OTP.", Colors.orange);
        }
      }
      
      // 2. Send Password Reset Email
      await _auth.sendPasswordResetEmail(email: userEmail);

      _showSnackBar("PIN reset link sent to $userEmail. Use the link to set a NEW Vault PIN.", Colors.green);
      await _auth.signOut(); 

    } catch (e) {
      _showSnackBar("Recovery failed. Check network.", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Navigation & UI Helpers ---
  void _showSnackBar(String message, [Color color = Colors.green]) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    // AuthWrapper handles redirection
  }

  @override
  Widget build(BuildContext context) {
    const Color purpleDark = Color(0xFF6A5AE3);
    
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: purpleDark))
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Settings", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              
              const SizedBox(height: 16),

              // 1. PROTECTION SETTINGS Card
              _buildSettingCard(
                title: "Protection Settings",
                widgets: [
                  _buildToggleRow(
                    title: "Gesture Detection",
                    subtitle: "Monitor camera for emergency gestures",
                    value: _isGestureDetectionEnabled,
                    onChanged: (v) => setState(() {
                      _isGestureDetectionEnabled = v;
                      _updateSetting('isGestureDetectionEnabled', v);
                    }),
                  ),
                  _buildToggleRow(
                    title: "Voice Detection",
                    subtitle: "Monitor for custom trigger word",
                    value: _isVoiceDetectionEnabled,
                    onChanged: (v) => setState(() {
                      _isVoiceDetectionEnabled = v;
                      _updateSetting('isVoiceDetectionEnabled', v);
                    }),
                  ),
                  _buildToggleRow(
                    title: "Live Location",
                    subtitle: "Continuously share GPS location",
                    value: _isLiveLocationEnabled,
                    onChanged: (v) => setState(() {
                      _isLiveLocationEnabled = v;
                      _updateSetting('isLiveLocationEnabled', v);
                    }),
                  ),
                   _buildToggleRow(
                    title: "Background Running",
                    subtitle: "Allow app to run in background",
                    value: _isBackgroundRunningEnabled,
                    onChanged: (v) => setState(() {
                      _isBackgroundRunningEnabled = v;
                      _updateSetting('isBackgroundRunningEnabled', v);
                    }),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),

              // 2. VOICE TRIGGER Card
              _buildSettingCard(
                title: "Voice Trigger",
                widgets: [
                  ListTile(
                    title: const Text("Current Trigger Word"),
                    subtitle: Text(_currentTriggerWord, style: const TextStyle(fontWeight: FontWeight.bold, color: purpleDark, fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                    child: TextField(
                      controller: _voiceTriggerController,
                      decoration: InputDecoration(
                        labelText: "New Trigger Word",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _updateTriggerWord,
                        icon: const Icon(Icons.mic),
                        label: const Text("Update Trigger Word"),
                        style: ElevatedButton.styleFrom(backgroundColor: purpleDark, foregroundColor: Colors.white),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            onPressed: _testVoiceRecognition,
                            icon: const Icon(Icons.volume_up, color: purpleDark),
                            label: const Text("Test Voice", style: TextStyle(color: purpleDark)),
                          ),
                          TextButton.icon(
                            onPressed: _testLocationServices,
                            icon: const Icon(Icons.location_on, color: purpleDark),
                            label: const Text("Test Location", style: TextStyle(color: purpleDark)),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: _resetOnboarding,
                        icon: const Icon(Icons.refresh, color: Colors.orange),
                        label: const Text("Reset Onboarding (Debug)", style: TextStyle(color: Colors.orange)),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 20),

              // 3. SECURITY & RECOVERY
              _buildSettingCard(
                title: "Security and Recovery",
                widgets: [
                   ListTile(
                    leading: const Icon(Icons.key, color: Colors.blue),
                    title: const Text("Reset Secure Vault PIN"),
                    subtitle: const Text("Initiate recovery using Biometrics and Email."),
                    trailing: const Icon(Icons.lock_reset),
                    onTap: _forgotPinFlow,
                  ),
                  const ListTile(
                    leading: Icon(Icons.timer, color: purpleDark),
                    title: Text("SOS Repeat Interval"),
                    subtitle: Text("Currently set to 2 minutes"), // Hardcode for now
                    trailing: Icon(Icons.edit),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 4. USER & APP INFO
              _buildSettingCard(
                title: "App Information",
                widgets: [
                  ListTile(
                    leading: const Icon(Icons.info, color: Colors.grey),
                    title: const Text("App Guidelines"),
                    subtitle: const Text("How every feature works (Gesture, Voice, SOS Flow)"),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppGuidelinesScreen()));
                    },
                  ),
                  const ListTile(
                    leading: Icon(Icons.policy, color: purpleDark),
                    title: Text("Privacy Policy"),
                    trailing: Icon(Icons.open_in_new),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // 5. Logout Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _logout,
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text("Log Out"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
        if (_isLoading)
          Container(color: Colors.black.withOpacity(0.5), child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        ],
      ),
    );
  }
    
    // Helper to build a general setting card style
  Widget _buildSettingCard({required String title, required List<Widget> widgets}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: widgets,
          ),
        ),
      ],
    );
  }

  // Helper to build a standardized toggle row
  Widget _buildToggleRow({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.green),
      onTap: () => onChanged(!value), // Allows tapping the whole row
    );
  }
}