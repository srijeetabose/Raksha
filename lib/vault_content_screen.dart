// lib/vault_content_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:raksha/home_screen.dart'; 

class VaultContentScreen extends StatefulWidget {
  const VaultContentScreen({super.key});

  @override
  State<VaultContentScreen> createState() => _VaultContentScreenState();
}

class _VaultContentScreenState extends State<VaultContentScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  bool _isRecordingActive = false; 

  @override
  void initState() {
    super.initState();
    _checkRecordingStatus();
  }
  
  // Check if there's an active emergency recording
  Future<void> _checkRecordingStatus() async {
    try {
      final activeRecordings = await _firestore.collection('emergency_recordings')
          .where('userId', isEqualTo: _auth.currentUser!.uid)
          .where('status', isEqualTo: 'recording')
          .limit(1)
          .get();
      
      if (mounted) {
        setState(() {
          _isRecordingActive = activeRecordings.docs.isNotEmpty;
        });
      }
    } catch (e) {
      // debug removed
    }
  }

  // --- I AM SAFE Logic (Stops Recording and Finalizes Alert) ---
  Future<void> _stopRecordingAndFinalize() async {
    try {
      // 1. Send signal to Native Service to STOP stealth recording
      const platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('stopStealthRecording');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(" Stealth recording stopped. Uploading to secure cloud storage..."),
          backgroundColor: Colors.green,
        ),
      );
      
      // 2. Stop the recording state in the UI
      if (mounted) {
        setState(() {
          _isRecordingActive = false;
        });
      }

      // 3. Update Firestore with "safe" status
      final activeRecordings = await _firestore.collection('emergency_recordings')
          .where('userId', isEqualTo: _auth.currentUser!.uid)
          .where('status', isEqualTo: 'recording')
          .orderBy('startTimestamp', descending: true)
          .limit(1)
          .get();

      if (activeRecordings.docs.isNotEmpty) {
        await activeRecordings.docs.first.reference.update({
          'status': 'safe',
          'safeTimestamp': FieldValue.serverTimestamp(),
          'userConfirmedSafe': true,
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(" Emergency status updated to SAFE. Recordings are being uploaded to permanent cloud storage."),
            backgroundColor: Colors.blue,
          ),
        );
      }

      // Navigate back to the main Home Screen
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
          
    } catch (e) {
      // debug removed
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error stopping recording: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- Fetch Recordings from Firestore (Persistence Logic) ---
  Stream<QuerySnapshot> _fetchRecordings() {
    // Fetches emergency recordings that have been uploaded to cloud storage
    return _firestore.collection('emergency_recordings')
        .where('userId', isEqualTo: _auth.currentUser!.uid)
        .where('status', whereIn: ['safe', 'uploaded'])
        .orderBy('startTimestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Secure Vault (Tamper-Proof)")),
      body: Column(
        children: [
          //  CRITICAL: I AM SAFE Button (Shows only if recording is active)
          if (_isRecordingActive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.red,
              child: MaterialButton(
                onPressed: _stopRecordingAndFinalize,
                color: Colors.white,
                child: const Text(
                  "I AM SAFE (STOP RECORDING)",
                  style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Evidence is stored securely on Firebase Storage (not your gallery) and CANNOT be deleted.",
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),

          // List of Recordings
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _fetchRecordings(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No secure recordings found."));
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final timestamp = DateTime.fromMillisecondsSinceEpoch(data['startTimestamp'] ?? 0);
                    final gesture = data['gesture'] ?? 'Unknown';
                    final recordingId = data['recordingId'] ?? 'Unknown';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.security, color: Colors.red, size: 32),
                        title: Text(
                          "Emergency Recording",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Gesture: $gesture"),
                            Text("Date: ${timestamp.toString().substring(0, 16)}"),
                            Text("ID: ${recordingId.substring(0, 12)}..."),
                            const Text(
                              " PERMANENT - Cannot be deleted",
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_done, color: Colors.green),
                            const Text(
                              "UPLOADED",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          // Show recording details
                          _showRecordingDetails(data);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // Show recording details dialog
  void _showRecordingDetails(Map<String, dynamic> data) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(data['startTimestamp'] ?? 0);
    final gesture = data['gesture'] ?? 'Unknown';
    final recordingId = data['recordingId'] ?? 'Unknown';
    final deviceInfo = data['deviceInfo'] as Map<String, dynamic>? ?? {};
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          " Emergency Recording Details",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow("Trigger Gesture:", gesture),
            _buildDetailRow("Date & Time:", timestamp.toString()),
            _buildDetailRow("Recording ID:", recordingId),
            _buildDetailRow("Device:", "${deviceInfo['manufacturer']} ${deviceInfo['model']}"),
            _buildDetailRow("Android Version:", deviceInfo['androidVersion'] ?? 'Unknown'),
            const SizedBox(height: 16),
            const Text(
              " Files Included:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text("• Audio recording (3GP format)"),
            const Text("• Video recording (MP4 format)"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: const Text(
                " SECURITY NOTICE:\nThese recordings are permanently stored in encrypted cloud storage and cannot be deleted by anyone, including the user. They serve as tamper-proof evidence.",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}