// lib/onboarding_voice_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:raksha/home_screen.dart';

class OnboardingVoiceScreen extends StatefulWidget {
  const OnboardingVoiceScreen({super.key});

  @override
  State<OnboardingVoiceScreen> createState() => _OnboardingVoiceScreenState();
}

class _OnboardingVoiceScreenState extends State<OnboardingVoiceScreen> {
  // 30 less common words for better security
  final List<String> availableWords = [
    'Sunset', 'Cobalt', 'Anchor', 'Whisper', 'Thunder', 'Crystal',
    'Shadow', 'Velvet', 'Phoenix', 'Marble', 'Silver', 'Crimson',
    'Glacier', 'Ember', 'Sapphire', 'Raven', 'Ivory', 'Copper',
    'Mystic', 'Prism', 'Falcon', 'Jade', 'Storm', 'Pearl',
    'Onyx', 'Flame', 'Frost', 'Ruby', 'Steel', 'Violet'
  ];
  
  List<String> selectedWords = [];
  bool _isLoading = false;
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadExistingWords();
  }

  Future<void> _loadExistingWords() async {
    if (_userId == null) return;
    
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
      if (doc.exists && doc.data() != null) {
        final savedWords = doc.data()!['triggerVoiceWords'] as List<dynamic>?;
        if (savedWords != null) {
          setState(() {
            selectedWords = savedWords.cast<String>();
          });
        }
      }
    } catch (e) {
      print('Error loading existing words: $e');
    }
  }

  void _toggleWord(String word) {
    setState(() {
      if (selectedWords.contains(word)) {
        selectedWords.remove(word);
      } else if (selectedWords.length < 3) {
        selectedWords.add(word);
      }
    });
  }

  Future<void> _saveWordsAndContinue() async {
    if (selectedWords.length != 3) {
      _showSnackBar("Please select exactly 3 trigger words.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).update({
        'triggerVoiceWords': selectedWords, // Fixed field name to match loading
        'voiceTriggers': selectedWords, // Keep both for compatibility
        'isVoiceDetectionEnabled': true,
        'onboardingStep': 'voice_complete',
      });

      _showSnackBar("Voice triggers saved successfully!");
      
      // Navigate to home screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      _showSnackBar("Failed to save voice triggers. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color purpleDark = Color(0xFF6A5AE3);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF936EE4), Color(0xFF6A5AE3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.mic, size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      "Voice Trigger Setup",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Select exactly 3 words. Say 'Raksha [word]' to trigger SOS",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Selected: ${selectedWords.length}/3",
                        style: TextStyle(
                          color: selectedWords.length == 3 ? Colors.green[200] : Colors.orange[200],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Word Selection Grid
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Choose Your Trigger Words",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: purpleDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: availableWords.length,
                          itemBuilder: (context, index) {
                            final word = availableWords[index];
                            final isSelected = selectedWords.contains(word);
                            final canSelect = selectedWords.length < 3 || isSelected;

                            return GestureDetector(
                              onTap: canSelect ? () => _toggleWord(word) : null,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected 
                                      ? purpleDark 
                                      : canSelect 
                                          ? Colors.grey[100] 
                                          : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? purpleDark : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    word,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 14,
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
                ),
              ),

              // Bottom Section
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // Example Usage
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "Example Usage:",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (selectedWords.isNotEmpty)
                            Text(
                              '"Raksha ${selectedWords.first}"',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading || selectedWords.length != 3 
                            ? null 
                            : _saveWordsAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: purpleDark,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : const Text(
                                "Save Voice Triggers",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Skip Button
                    TextButton(
                      onPressed: _isLoading ? null : () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                          (route) => false,
                        );
                      },
                      child: const Text(
                        "Skip Voice Setup",
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}