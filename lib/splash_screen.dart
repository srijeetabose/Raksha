// lib/splash_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
// This is the new import
import 'package:raksha/auth_wrapper.dart'; // Import AuthWrapper

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // This is the 5-second timer
    Timer(const Duration(seconds: 5), () {
      // This is the new navigation line
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthWrapper()), // Go to AuthWrapper
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // This creates the purple gradient background
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF936EE4), // Start color
              Color(0xFF6A5AE3), // End color
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // This shows your logo from 'assets/images/raksha_logo.png'
              Image.asset(
                'assets/images/raksha_logo.png',
                width: 160,
                height: 160,
              ),
              const SizedBox(height: 20), // Spacing

              // "RAKSHA" text
              const Text(
                "RAKSHA",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),

              // "YOU ARE NEVER ALONE" text
              const Text(
                "YOU ARE NEVER ALONE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}