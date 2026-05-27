// lib/app_guidelines_screen.dart

import 'package:flutter/material.dart';

class AppGuidelinesScreen extends StatelessWidget {
  const AppGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("App Guidelines", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF6A5AE3),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Gesture Detection Card
            _buildInfoCard(
              icon: Icons.camera_alt,
              title: "Gesture Detection",
              body: [
                _buildBulletPoint("The app uses your front camera to detect emergency hand gestures in real-time."),
                _buildBulletPoint("Choose from 4 pre-trained gestures (Peace, Thumbs Up, Fist, Four Fingers)."),
                _buildBulletPoint("Works even in low light or partial view. Runs silently in the background."),
                _buildBulletPoint("AI model detects stressed or quick gestures (requires no manual training)."),
              ],
            ),
            const SizedBox(height: 20),

            // 2. Voice Triggers Card
            _buildInfoCard(
              icon: Icons.mic,
              title: "Voice Triggers",
              body: [
                _buildBulletPoint("Set a custom safe word (e.g., \"Strawberry\", \"Rainbow\") that triggers emergency when spoken."),
                _buildBulletPoint("Works even if said within a sentence (e.g., \"I think the word is strawberry now\")."),
                _buildBulletPoint("Detects stressed or whispered voice. Works offline—no internet needed."),
                _buildBulletPoint("Continuous background listening with low battery consumption."),
              ],
            ),
            const SizedBox(height: 20),

            // 3. SOS Activation Process Card
            _buildInfoCard(
              icon: Icons.warning,
              title: "SOS Activation Process",
              body: [
                _buildNumberedStep(1, "Silent popup appears: \"SOS about to trigger\" (10 seconds to cancel)."),
                _buildNumberedStep(2, "If not cancelled: Phone vibrates for 5 seconds (final warning)."),
                _buildNumberedStep(3, "Emergency activated: Recording starts, contacts notified, police contacted."),
              ],
            ),
            const SizedBox(height: 20),

            // 4. Emergency Contacts Card
            _buildInfoCard(
              icon: Icons.group,
              title: "Emergency Contacts",
              body: [
                _buildBulletPoint("Add up to 5 trusted contacts who will be notified during emergencies (Max 5)."),
                _buildBulletPoint("Automatically sends SMS with your current location and a custom emergency message."),
                _buildBulletPoint("Sends live location updates every 30 seconds. Works even if internet is down (uses SMS)."),
              ],
            ),
            const SizedBox(height: 20),

            // 5. Police Station Connection Card
            _buildInfoCard(
              icon: Icons.local_police,
              title: "Police Station Connection",
              body: [
                _buildBulletPoint("Automatically connects to the nearest verified police station using GPS."),
                _buildBulletPoint("Sends live location and emergency details, including audio/video recording links."),
                _buildBulletPoint("Backup SMS to local emergency services if the app link is unavailable."),
              ],
            ),
            const SizedBox(height: 20),

            // 6. Stealth Mode Card
            _buildInfoCard(
              icon: Icons.visibility_off,
              title: "Stealth Mode",
              body: [
                _buildBulletPoint("App disappears from home screen and app drawer while maintaining protection."),
                _buildBulletPoint("Access via secret dialer code (e.g., **#1234)."),
                _buildBulletPoint("All protection features remain active. No notifications or visible indicators."),
                _buildBulletPoint("Perfect for situations requiring discretion."),
              ],
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
  
  // Helper to build a section card
  Widget _buildInfoCard({required IconData icon, required String title, required List<Widget> body}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF6A5AE3), size: 30),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            ...body,
          ],
        ),
      ),
    );
  }

  // Helper for bullet points
  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  // Helper for numbered steps
  Widget _buildNumberedStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text("$number", style: const TextStyle(color: Colors.white, fontSize: 12))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}