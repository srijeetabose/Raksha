// lib/secure_vault_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io';
import 'audio_player_screen.dart';

class SecureVaultScreen extends StatefulWidget {
  const SecureVaultScreen({super.key});

  @override
  State<SecureVaultScreen> createState() => _SecureVaultScreenState();
}

class _SecureVaultScreenState extends State<SecureVaultScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isBiometricVerified = false;
  bool _showPasswordOption = false;
  List<Map<String, dynamic>> _recordings = [];
  bool _canCheckBiometrics = false;
  List<BiometricType> _availableBiometrics = [];

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  // Check if device supports biometric authentication
  Future<void> _checkBiometricSupport() async {
    try {
      _canCheckBiometrics = await _localAuth.canCheckBiometrics;
      _availableBiometrics = await _localAuth.getAvailableBiometrics();
      
      print("✅ Can check biometrics: $_canCheckBiometrics");
      print("✅ Available biometrics: $_availableBiometrics");
      
      setState(() {});
    } catch (e) {
      print("❌ Error checking biometric support: $e");
      _canCheckBiometrics = false;
    }
  }

  // Authenticate with biometrics (fingerprint/face)
  Future<void> _authenticateWithBiometrics() async {
    setState(() => _isLoading = true);

    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access Secure Vault emergency recordings',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        setState(() {
          _isBiometricVerified = true;
        });
        await _loadSecureVaultRecordings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Authentication failed"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print("❌ Biometric authentication error: $e");
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
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("❌ No user logged in");
        setState(() {
          _recordings = [];
        });
        return;
      }
      
      print("📋 Loading recordings from Firebase for user: $userId");
      
      // Load recordings from Firebase
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('secureVaultRecordings')
            .orderBy('startTime', descending: true)
            .get();
        
        setState(() {
          _recordings = snapshot.docs.map((doc) => doc.data()).toList();
        });
        
        print("✅ Loaded ${_recordings.length} recordings from Firebase");
      } catch (e) {
        print("❌ Firebase error: $e");
        
        // Show error message to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "⚠️ Cannot load recordings: Firebase permission error\n\n"
                "Please update Firestore rules in Firebase Console:\n"
                "match /users/{userId}/secureVaultRecordings/{recordingId} {\n"
                "  allow read, write: if request.auth != null && request.auth.uid == userId;\n"
                "}"
              ),
              duration: const Duration(seconds: 10),
              backgroundColor: Colors.orange,
            ),
          );
        }
        
        setState(() {
          _recordings = [];
        });
      }
    } catch (e) {
      print("❌ Error loading recordings: $e");
      setState(() {
        _recordings = [];
      });
    }
  }

  Future<void> _playRecording(Map<String, dynamic> recording) async {
    try {
      final audioPath = recording['audioPath'] as String?;
      final videoPath = recording['videoPath'] as String?;
      final gesture = recording['gesture'] as String? ?? 'Unknown';
      final timestamp = recording['startTime'] as int?;

      if (audioPath == null && videoPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ No recording paths found")),
        );
        return;
      }

      // Show choice dialog if both exist
      if (videoPath != null && audioPath != null) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Play Recording"),
            content: const Text("Choose what to play:"),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.mic, color: Color(0xFF6A5AE3)),
                label: const Text("Audio"),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AudioPlayerScreen(
                      audioPath: audioPath,
                      videoPath: null,
                      gesture: gesture,
                      timestamp: timestamp,
                    ),
                  ));
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.videocam),
                label: const Text("Video"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A5AE3),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _openVideoFile(videoPath);
                },
              ),
            ],
          ),
        );
        return;
      }

      // Only audio
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => AudioPlayerScreen(
          audioPath: audioPath,
          videoPath: videoPath,
          gesture: gesture,
          timestamp: timestamp,
        ),
      ));
      
    } catch (e) {
      print("❌ Error playing recording: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error: $e"),
          duration: const Duration(seconds: 5),
        ),
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
      body: _isBiometricVerified ? _buildVaultContent() : _buildBiometricEntry(),
    );
  }

  Widget _buildBiometricEntry() {
    if (_showPasswordOption) {
      return _buildPasswordEntry();
    }
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _availableBiometrics.contains(BiometricType.face)
                ? Icons.face
                : Icons.fingerprint,
            size: 100,
            color: Colors.purple,
          ),
          const SizedBox(height: 24),
          const Text(
            "Biometric Authentication Required",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            "Emergency recordings are stored securely in the cloud and can only be accessed with biometric authentication.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Recordings cannot be deleted and persist even after app uninstall",
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (!_canCheckBiometrics)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: const Column(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 32),
                  SizedBox(height: 8),
                  Text(
                    "Biometric authentication not available",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Use password option below to access vault",
                    style: TextStyle(fontSize: 12, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _authenticateWithBiometrics,
                icon: Icon(
                  _availableBiometrics.contains(BiometricType.face)
                      ? Icons.face
                      : Icons.fingerprint,
                  color: Colors.white,
                ),
                label: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _availableBiometrics.contains(BiometricType.face)
                            ? "Authenticate with Face ID"
                            : "Authenticate with Fingerprint",
                        style: const TextStyle(fontSize: 16),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            "OR",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showPasswordOption = true;
              });
            },
            icon: const Icon(Icons.password, color: Colors.purple),
            label: const Text(
              "Use Password Instead",
              style: TextStyle(
                color: Colors.purple,
                fontSize: 16,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordEntry() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock,
            size: 80,
            color: Colors.purple,
          ),
          const SizedBox(height: 24),
          const Text(
            "Enter Your Password",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            "Use your Raksha account password to access the secure vault.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: "Password",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
            onSubmitted: (_) => _authenticateWithPassword(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _authenticateWithPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Unlock Vault", style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _forgotPassword,
            child: const Text(
              "Forgot Password?",
              style: TextStyle(
                color: Colors.purple,
                fontSize: 16,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_canCheckBiometrics)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showPasswordOption = false;
                  _passwordController.clear();
                });
              },
              icon: const Icon(Icons.fingerprint, color: Colors.purple),
              label: const Text(
                "Use Biometric Instead",
                style: TextStyle(
                  color: Colors.purple,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Authenticate with password
  Future<void> _authenticateWithPassword() async {
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ No user logged in")),
        );
        return;
      }

      // Re-authenticate user with password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _passwordController.text,
      );

      await user.reauthenticateWithCredential(credential);

      // Password is correct
      setState(() {
        _isBiometricVerified = true;
      });
      await _loadSecureVaultRecordings();
      
      _passwordController.clear();
    } on FirebaseAuthException catch (e) {
      String errorMessage = "❌ Authentication failed";
      if (e.code == 'wrong-password') {
        errorMessage = "❌ Incorrect password";
      } else if (e.code == 'too-many-requests') {
        errorMessage = "❌ Too many attempts. Try again later";
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Forgot password - Send reset email
  Future<void> _forgotPassword() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ No email found for this account")),
        );
        return;
      }

      // Show confirmation dialog
      bool confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("🔐 Reset Password"),
              content: Text(
                "A password reset link will be sent to:\n\n${user.email}\n\n"
                "After resetting your password, you can use it to access the Secure Vault."
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  child: const Text("Send Email", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;

      setState(() => _isLoading = true);

      // Send password reset email
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Password reset email sent to ${user.email}"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );

      // Show instructions dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("📧 Check Your Email"),
          content: const Text(
            "We've sent a password reset link to your email.\n\n"
            "Steps:\n"
            "1. Check your email inbox\n"
            "2. Click the reset link\n"
            "3. Set a new password\n"
            "4. Return to this screen\n"
            "5. Use your new password to access Secure Vault\n\n"
            "Note: You don't need to log out. Just reset your password and use it here."
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              child: const Text("OK", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
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
                      final isRecording = recording['status'] == 'recording';
                      final hasAudio = recording['hasAudio'] == true;
                      final hasVideo = recording['hasVideo'] == true;
                      final audioPath = recording['audioPath'] as String?;
                      final videoPath = recording['videoPath'] as String?;
                      
                      // Check if files actually exist
                      final canPlay = !isRecording && (audioPath != null || videoPath != null);
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isRecording ? Colors.orange : Colors.red,
                            child: Icon(
                              isRecording ? Icons.fiber_manual_record : Icons.emergency,
                              color: Colors.white,
                            ),
                          ),
                          title: Text("Emergency: ${recording['gesture']}"),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Time: ${_formatTimestamp(recording['startTime'])}"),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    isRecording ? Icons.fiber_manual_record : Icons.check_circle,
                                    size: 14,
                                    color: isRecording ? Colors.orange : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isRecording ? "Recording..." : "Saved",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isRecording ? Colors.orange : Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (hasAudio)
                                    const Icon(Icons.mic, size: 14, color: Colors.green),
                                  if (hasVideo)
                                    const Icon(Icons.videocam, size: 14, color: Colors.red),
                                ],
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.play_arrow, 
                              color: canPlay ? Colors.purple : Colors.grey,
                            ),
                            onPressed: canPlay ? () => _playRecording(recording) : null,
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
  
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "Unknown";
    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp as int);
      return "${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return timestamp.toString();
    }
  }
  
  Future<void> _openVideoFile(String videoPath) async {
    try {
      const channel = MethodChannel('com.raksha/sos_service');
      await channel.invokeMethod('openVideoFile', {'path': videoPath});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot play video: $e')),
        );
      }
    }
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
      
      // Send "I am safe" broadcast to reset voice trigger cooldown
      await sosChannel.invokeMethod('sendIAmSafeBroadcast');
      
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