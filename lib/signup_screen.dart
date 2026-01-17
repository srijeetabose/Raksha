// lib/signup_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

// This enum defines the mode, like your RadioGroup
enum AuthMode { user, police }

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  AuthMode _authMode = AuthMode.user;
  bool _isLoading = false;
  File? _policeIdImage;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _policeIdController = TextEditingController();

  final _firebaseAuth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _firebaseStorage = FirebaseStorage.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _policeIdController.dispose();
    super.dispose();
  }

  // --- Image Picker Logic: MODIFIED FOR CAMERA ONLY ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 70); // Force camera, higher quality

    if (pickedFile != null) {
      setState(() {
        _policeIdImage = File(pickedFile.path);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Official ID captured successfully!")), // Updated message
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No image captured.")),
      );
    }
  }

  // --- Main Sign Up Logic (Same as previous step, just re-included for context) ---
  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final policeId = _policeIdController.text.trim();
    final isPolice = _authMode == AuthMode.police;

    if (name.isEmpty || email.isEmpty || phone.isEmpty || password.length < 6 || (isPolice && policeId.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields and ensure password is 6+ characters.")),
      );
      return;
    }
    if (isPolice && _policeIdImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Police Mode requires an Official ID card to be captured.")),
      );
      return;
    }

    setState(() => _isLoading = true);
    String? storageUrl;

    try {
      final UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final userId = userCredential.user!.uid;

      if (isPolice && _policeIdImage != null) {
        final ref = _firebaseStorage
            .ref()
            .child('police_ids')
            .child(userId)
            .child('proof_${DateTime.now().millisecondsSinceEpoch}.jpg');

        await ref.putFile(_policeIdImage!);
        storageUrl = await ref.getDownloadURL();
      }

      final Map<String, dynamic> userData = {
        'name': name,
        'email': email,
        'phone': phone,
        'userRole': isPolice ? 'police' : 'user',
        'onboardingComplete': false,
      };

      await _firestore.collection('users').doc(userId).set(userData);

      if (isPolice) {
        await _firestore.collection('police_verification').doc(userId).set({
          'fullName': name,
          'email': email,
          'phone': phone,
          'policeIdNumber': policeId,
          'idProofUrl': storageUrl,
          'verificationStatus': 'pending', // CRITICAL for manual review
          'submittedAt': FieldValue.serverTimestamp(),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isPolice ? "Account created. Verification pending." : "Account created successfully!")),
      );

      Navigator.of(context).pop();

    } on FirebaseAuthException catch (e) {
      String message = "Sign up failed.";
      if (e.code == 'email-already-in-use') {
        message = "User already exists with this email, please login.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      print("General Sign Up Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("An unexpected error occurred.")),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- UI and Widget Building ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF936EE4), Color(0xFF6A5AE3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 64),
                      const Text(
                        "Create Account",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Mode Toggle (User/Police)
                      ToggleButtons(
                        isSelected: [
                          _authMode == AuthMode.user,
                          _authMode == AuthMode.police,
                        ],
                        onPressed: (index) {
                          setState(() {
                            _authMode =
                                (index == 0) ? AuthMode.user : AuthMode.police;
                            _policeIdImage = null; // Clear image if mode changes
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        selectedColor: const Color(0xFF6A5AE3),
                        color: Colors.white,
                        fillColor: Colors.white,
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text("User Mode"),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text("Police Mode"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      TextField(
                        controller: _nameController,
                        decoration: _buildInputDecoration("Full Name"),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _buildInputDecoration("Email"),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _buildInputDecoration("Phone Number"),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: _buildInputDecoration("Password"),
                      ),
                      const SizedBox(height: 16),

                      // --- Police Only Fields ---
                      if (_authMode == AuthMode.police)
                        Column(
                          children: [
                            TextField(
                              controller: _policeIdController,
                              decoration: _buildInputDecoration("Police ID / Badge Number"),
                            ),
                            const SizedBox(height: 16),

                            // Upload ID Button - Text Changed
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _pickImage, // LINKED TO CAMERA ONLY
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(_policeIdImage == null ? "Capture Official ID Card" : "Official ID Captured"), // TEXT CHANGE
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),

                      // Sign Up Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF6A5AE3),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "Sign Up",
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Login Link
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.of(context).pop();
                              },
                        child: const Text(
                          "Already have an account? Login",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
    );
  }
}