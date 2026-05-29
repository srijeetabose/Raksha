// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:raksha/firebase_options.dart'; // Make sure this file exists
import 'package:raksha/splash_screen.dart';   // Import your new splash screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raksha',
      theme: ThemeData(
        primarySwatch: Colors.purple,
      ),
      // This is the important line:
      home: const SplashScreen(), // This shows your splash screen first
      debugShowCheckedModeBanner: false,
    );
  }
}