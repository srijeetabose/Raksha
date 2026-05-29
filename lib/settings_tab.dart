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
  List<String> _currentTriggerWords = [];
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
            _isBackgroundRunningEnabled = data['isBackgroundRunningEnabled'] ?? true;
            _currentTriggerWords = (data['triggerVoiceWords'] as List<dynamic>?)?.cast<String>()
                ?? (data['voiceTriggers'] as List<dynamic>?)?.cast<String>()
                ?? [];
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
      if (_currentTriggerWords.isEmpty) {
        _showSnackBar("No voice triggers set up. Please configure voice triggers first.", Colors.orange);
      } else {
        await _restartBackgroundService();
        _showSnackBar("Voice recognition active. Try saying: ${_currentTriggerWords.join(', ')}", Colors.blue);
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
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
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
                title: "Voice Trigger Words",
                widgets: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _currentTriggerWords.isEmpty
                        ? const ListTile(
                            leading: Icon(Icons.warning_amber, color: Colors.orange),
                            title: Text("No trigger words set"),
                            subtitle: Text("Tap below to configure your 3 emergency words"),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _currentTriggerWords.map((word) => Chip(
                              label: Text(word, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              backgroundColor: const Color(0xFF6A5AE3),
                              avatar: const Icon(Icons.mic, color: Colors.white, size: 16),
                            )).toList(),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const _VoiceWordPickerSheet()),
                          );
                          _loadSettings(); // Reload after returning
                        },
                        icon: const Icon(Icons.edit),
                        label: Text(_currentTriggerWords.isEmpty ? "Set Trigger Words" : "Change Trigger Words"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A5AE3),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: _testVoiceRecognition,
                        icon: const Icon(Icons.volume_up, color: Color(0xFF6A5AE3)),
                        label: const Text("Test Voice", style: TextStyle(color: Color(0xFF6A5AE3))),
                      ),
                      TextButton.icon(
                        onPressed: _testLocationServices,
                        icon: const Icon(Icons.location_on, color: Color(0xFF6A5AE3)),
                        label: const Text("Test Location", style: TextStyle(color: Color(0xFF6A5AE3))),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _resetOnboarding,
                    icon: const Icon(Icons.refresh, color: Colors.orange),
                    label: const Text("Reset Onboarding (Debug)", style: TextStyle(color: Colors.orange)),
                  ),
                  const SizedBox(height: 8),
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

// Inline word picker screen for changing trigger words from settings
class _VoiceWordPickerSheet extends StatefulWidget {
  const _VoiceWordPickerSheet();

  @override
  State<_VoiceWordPickerSheet> createState() => _VoiceWordPickerSheetState();
}

class _VoiceWordPickerSheetState extends State<_VoiceWordPickerSheet> {
  static const List<String> _availableWords = [
    'Help', 'Danger', 'Emergency', 'Police', 'Rescue', 'Attack',
    'Fire', 'Thief', 'Intruder', 'Accident', 'Medical', 'Urgent',
    'Crisis', 'Threat', 'Alarm', 'Alert', 'Panic', 'Trouble',
    'Assist', 'Save', 'Stop', 'Run', 'Escape', 'Protect',
    'Call', 'Now', 'Quick', 'Fast', 'Immediate', 'SOS',
  ];

  List<String> _selected = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final words = (data['triggerVoiceWords'] as List<dynamic>?)?.cast<String>()
            ?? (data['voiceTriggers'] as List<dynamic>?)?.cast<String>()
            ?? [];
        if (mounted) {
          final normalized = words.map((t) {
            return _availableWords.firstWhere(
              (w) => w.toLowerCase() == t.toLowerCase(),
              orElse: () => t,
            );
          }).toList();
          setState(() => _selected = normalized);
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_selected.length != 3) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'triggerVoiceWords': _selected,
        'voiceTriggers': _selected,
        'isVoiceDetectionEnabled': true,
      }, SetOptions(merge: true));

      // Immediately push new triggers to the running background service
      try {
        await SosServiceChannel.startBackgroundService([], _selected);
        print("✅ Service restarted with new triggers: $_selected");
      } catch (e) {
        print("⚠️ Could not restart service: $e");
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const purpleDark = Color(0xFF6A5AE3);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose 3 Trigger Words'),
        backgroundColor: purpleDark,
        foregroundColor: Colors.white,
        actions: [
          if (_selected.length == 3)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: _selected.length == 3 ? Colors.green.shade50 : Colors.purple.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _selected.length == 3 ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: _selected.length == 3 ? Colors.green : purpleDark,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selected.length} / 3 selected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _selected.length == 3 ? Colors.green : purpleDark,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _availableWords.length,
              itemBuilder: (context, index) {
                final word = _availableWords[index];
                final isSelected = _selected.contains(word);
                final canSelect = _selected.length < 3 || isSelected;
                return InkWell(
                  onTap: canSelect
                      ? () => setState(() {
                            isSelected ? _selected.remove(word) : _selected.add(word);
                          })
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected ? purpleDark : canSelect ? Colors.grey[100] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.transparent : Colors.grey[300]!,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        word,
                        style: TextStyle(
                          color: isSelected ? Colors.white : canSelect ? Colors.black87 : Colors.grey[400],
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
