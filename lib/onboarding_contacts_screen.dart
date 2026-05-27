// lib/onboarding_contacts_screen.dart

import 'package:flutter/material.dart';
import 'package:raksha/home_screen.dart'; 

class OnboardingContactsScreen extends StatelessWidget {
  const OnboardingContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Setup: Emergency Contacts")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "CONTACTS SETUP (MANUAL ACCESS)", 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 10),
              const Text("This screen is now handled by the 'Contacts' tab on the main Home Screen."),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                    // Navigate to the main tab screen
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
                },
                child: const Text("Go to Home Screen"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}