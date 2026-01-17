// lib/secure_vault_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class SecureVaultScreen extends StatefulWidget {
  const SecureVaultScreen({super.key});

  @override
  State<SecureVaultScreen> createState() => _SecureVaultScreenState();
}

class _SecureVaultScreenState extends State<SecureVaultScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  bool _isPinVerified = false;
  List<Map<String, dynamic>> _recordings = [];

  @override
  void initState() {
    super.initState();
  }

  // Verify PIN
  Future<void> _verifyPin() async {
    if (_pinController.text.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a 4-digit PIN")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      // Get stored PIN hash
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      final storedPinHash = doc.data()?['secureVaultPinHash'] as String?;
      
      if (storedPinHash == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No PIN set. Please set up PIN in settings.")),
        );
        return;
      }

      // Hash entered PIN
      final enteredPinHash = sha256.convert(utf8.encode(_pinController.text)).toString();

      if (enteredPinHash == storedPinHash) {
        setState(() {
          _isPinVerified = true;
        });
        await _loadSecureVaultRecordings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Incorrect PIN"),
            backgroundColor: Colors.red,
          ),
        );
        _pinController.clear();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Load secure vault recordings
  Future<void> _loadSecureVaultRecordings() async {
    try {
      const sosChannel = MethodChannel('com.raksha/sos_service');
      final recordings = await sosChannel.invokeMethod('getSecureVaultRecordings');
      
      setState(() {
        _recordings = List<Map<String, dynamic>>.from(recordings);
      });
    } catch (e) {
      print("❌ Error loading recordings: $e");
    }
  }

  // Delete recording
  Future<void> _deleteRecording(String recordingId) async {
    try {
      const sosChannel = MethodChannel('com.raksha/sos_service');
      await sosChannel.invokeMethod('deleteSecureVaultRecording', {
        'recordingId': recordingId,
      });
      
      // Refresh list
      await _loadSecureVaultRecordings();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🗑️ Recording deleted")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Delete failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🔒 Secure Vault"),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: _isPinVerified ? _buildVaultContent() : _buildPinEntry(),
    );
  }

  Widget _buildPinEntry() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.security,
            size: 80,
            color: Colors.purple,
          ),
          const SizedBox(height: 24),
          const Text(
            "Enter PIN to Access Secure Vault",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            "Emergency recordings are stored securely and can only be accessed with your PIN.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: const InputDecoration(
              hintText: "••••",
              border: OutlineInputBorder(),
              counterText: "",
            ),
            onSubmitted: (_) => _verifyPin(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Unlock Vault"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple),
            ),
            child: Column(
              children: [
                const Icon(Icons.security, color: Colors.purple, size: 32),
                const SizedBox(height: 8),
                const Text(
                  "🔒 Secure Vault Unlocked",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${_recordings.length} emergency recordings found",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // I AM SAFE BUTTON - Stops all emergency recording
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                const SizedBox(height: 8),
                const Text(
                  "Emergency Status",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "If you are safe now, click the button below to stop all emergency recording and location sharing.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _stopAllEmergencyRecording,
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: const Text(
                      "I AM SAFE - STOP RECORDING",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _recordings.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "No emergency recordings found",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Recordings will appear here when SOS is triggered",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _recordings.length,
                    itemBuilder: (context, index) {
                      final recording = _recordings[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.red,
                            child: Icon(Icons.emergency, color: Colors.white),
                          ),
                          title: Text("Emergency: ${recording['gesture']}"),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Time: ${recording['startTime']}"),
                              Row(
                                children: [
                                  if (recording['hasAudio'] == true)
                                    const Icon(Icons.mic, size: 16, color: Colors.blue),
                                  if (recording['hasVideo'] == true)
                                    const Icon(Icons.videocam, size: 16, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text(
                                    "${recording['hasAudio'] == true ? 'Audio' : ''} ${recording['hasVideo'] == true ? 'Video' : ''}",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton(
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'play',
                                child: Row(
                                  children: [
                                    Icon(Icons.play_arrow),
                                    SizedBox(width: 8),
                                    Text('Play'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'delete') {
                                _showDeleteConfirmation(recording['id']);
                              } else if (value == 'play') {
                                _playRecording(recording);
                              }
                            },
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

  void _showDeleteConfirmation(String recordingId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Recording?"),
        content: const Text("This action cannot be undone. The emergency recording will be permanently deleted."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteRecording(recordingId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _playRecording(Map<String, dynamic> recording) {
    // TODO: Implement audio/video playback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🎥 Recording playback feature coming soon")),
    );
  }
  
  // Stop all emergency recording and location sharing
  Future<void> _stopAllEmergencyRecording() async {
    try {
      // Show confirmation dialog
      bool confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("🛡️ Confirm Safety"),
          content: const Text(
            "Are you sure you are safe?\n\n"
            "This will stop:\n"
            "• Emergency audio/video recording\n"
            "• Live location sharing\n"
            "• All SOS alerts\n\n"
            "Only click YES if you are truly safe."
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("YES, I AM SAFE", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ) ?? false;
      
      if (!confirmed) return;
      
      const sosChannel = MethodChannel('com.raksha/sos_service');
      
      // Stop emergency recording
      await sosChannel.invokeMethod('stopEmergencyRecording');
      
      // Stop location sharing
      const gestureChannel = MethodChannel('com.example.raksha/gesture_service');
      await gestureChannel.invokeMethod('stopLocationSharing');
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ All emergency recording and location sharing stopped. You are marked as safe."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      
      // Refresh recordings list
      await _loadSecureVaultRecordings();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error stopping recording: $e")),
      );
    }
  }
}