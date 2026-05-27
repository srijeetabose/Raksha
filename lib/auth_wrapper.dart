// lib/auth_wrapper.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:raksha/home_screen.dart';
import 'package:raksha/login_screen.dart';
import 'package:raksha/permissions_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // This is the Flutter equivalent of mAuth.getCurrentUser()
      // but it updates live whenever the auth state changes!
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Waiting for connection
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. User is logged in - check onboarding status
        if (snapshot.hasData) {
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(snapshot.data!.uid)
                .get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                final onboardingComplete = userData['onboardingComplete'] ?? false;

                // If onboarding is complete, go to home screen
                if (onboardingComplete) {
                  return const HomeScreen();
                }
                
                // If onboarding is not complete, start with permissions
                return const PermissionsScreen();
              }

              // If user document doesn't exist, start onboarding
              return const PermissionsScreen();
            },
          );
        }

        // 3. User is logged out
        return const LoginScreen();
      },
    );
  }
}