// lib/onboarding_voice_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:raksha/home_screen.dart';
import 'package:raksha/trigger_words_translations.dart';
import 'package:raksha/sos_service_channel.dart';

class OnboardingVoiceScreen extends StatefulWidget {
  const OnboardingVoiceScreen({super.key});

  @override
  State<OnboardingVoiceScreen> createState() => _OnboardingVoiceScreenState();
}

class _OnboardingVoiceScreenState extends State<OnboardingVoiceScreen> {
  List<String> availableWords = [
    'Help', 'Danger', 'Emergency', 'Police', 'Rescue', 'Attack',
    'Fire', 'Thief', 'Intruder', 'Accident', 'Medical', 'Urgent',
    'Crisis', 'Threat', 'Alarm', 'Alert', 'Panic', 'Trouble',
    'Assist', 'Save', 'Stop', 'Run', 'Escape', 'Protect',
    'Call', 'Now', 'Quick', 'Fast', 'Immediate', 'SOS'
  ];
  
  List<String> selectedWords = [];
  bool _isLoading = false;
  String _languageCode = 'en-IN';
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadExistingWords();
  }

  Future<void> _loadExistingWords() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final lang = data['voiceLanguage'] as String? ?? 'en-IN';
        final translatedWords = TriggerWordTranslations.getWords(lang);
        final savedTriggers = (data['triggerVoiceWords'] as List<dynamic>?)?.cast<String>()
            ?? (data['voiceTriggers'] as List<dynamic>?)?.cast<String>()
            ?? [];

        // Restore previously selected words — match case-insensitively against
        // the translated word list so the chips show as highlighted on re-open.
        final restoredSelection = savedTriggers.map((saved) {
          return translatedWords.firstWhere(
            (w) => w.toLowerCase() == saved.toLowerCase(),
            orElse: () => saved,
          );
        }).toList();

        if (mounted) {
          setState(() {
            _languageCode = lang;
            availableWords = translatedWords;
            // Restore the user's previously saved selection — do NOT reset to []
            selectedWords = restoredSelection;
          });
        }
      }
    } catch (e) {
      // ignore, start fresh
    }
  }

  void _toggleWord(String word) {
    setState(() {
      if (selectedWords.contains(word)) {
        // Remove if already selected
        selectedWords.remove(word);
      } else {
        // Add if less than 3 selected
        if (selectedWords.length < 3) {
          selectedWords.add(word);
        }
      }
    });
    print("Selected words: $selectedWords"); // Debug
  }

  Future<void> _saveWordsAndContinue() async {
    if (selectedWords.length != 3) {
      _showSnackBar("Please select exactly 3 trigger words.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).set({
        'triggerVoiceWords': selectedWords,
        'voiceTriggers': selectedWords, // Keep both for compatibility
        'isVoiceDetectionEnabled': true,
        'onboardingStep': 'voice_complete',
      }, SetOptions(merge: true));

      print("✅ Voice triggers saved: $selectedWords");

      // Immediately restart the background service with the new trigger words
      // so the running service picks them up without needing an app restart.
      try {
        await SosServiceChannel.startBackgroundService([], selectedWords);
        print("✅ Background service restarted with new triggers: $selectedWords");
      } catch (e) {
        print("⚠️ Could not restart service: $e");
      }

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
    const Color purpleLight = Color(0xFF936EE4);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF936EE4), Color(0xFF6A5AE3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Modern Header with Icon
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  children: [
                    // Icon with glow effect
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Title
                    const Text(
                      "Voice Trigger Setup",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Subtitle
                    Text(
                      "Choose 3 words in ${TriggerWordTranslations.getLanguageName(_languageCode)} that will activate emergency mode",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Selection Counter with modern design
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: selectedWords.length == 3 
                            ? Colors.green.withOpacity(0.3)
                            : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: selectedWords.length == 3 
                              ? Colors.greenAccent
                              : Colors.white.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selectedWords.length == 3 
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: selectedWords.length == 3 
                                ? Colors.greenAccent
                                : Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${selectedWords.length} / 3 Selected",
                            style: TextStyle(
                              color: selectedWords.length == 3 
                                  ? Colors.greenAccent
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Word Selection Card
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Card Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: purpleDark.withOpacity(0.05),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: purpleDark.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.touch_app_rounded,
                                color: purpleDark,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              "Tap to Select Words",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: purpleDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Word Grid
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2.2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: availableWords.length,
                            itemBuilder: (context, index) {
                              final word = availableWords[index];
                              final isSelected = selectedWords.contains(word);
                              final canSelect = selectedWords.length < 3 || isSelected;

                              return InkWell(
                                onTap: () {
                                  if (!isSelected && selectedWords.length >= 3) {
                                    setState(() {
                                      selectedWords.removeAt(0);
                                      selectedWords.add(word);
                                    });
                                  } else {
                                    _toggleWord(word);
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    gradient: isSelected 
                                        ? const LinearGradient(
                                            colors: [purpleLight, purpleDark],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    color: isSelected 
                                        ? null
                                        : canSelect 
                                            ? Colors.grey[100]
                                            : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected 
                                          ? Colors.transparent
                                          : canSelect
                                              ? Colors.grey[300]!
                                              : Colors.grey[400]!,
                                      width: 1.5,
                                    ),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: purpleDark.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ] : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      word,
                                      style: TextStyle(
                                        color: isSelected 
                                            ? Colors.white
                                            : canSelect
                                                ? Colors.black87
                                                : Colors.grey[500],
                                        fontWeight: isSelected 
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Section
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading || selectedWords.length != 3 
                            ? null 
                            : _saveWordsAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: purpleDark,
                          disabledBackgroundColor: Colors.white.withOpacity(0.3),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(purpleDark),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Continue",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: selectedWords.length == 3 
                                        ? purpleDark
                                        : Colors.grey,
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Skip Button
                    TextButton(
                      onPressed: _isLoading ? null : () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                          (route) => false,
                        );
                      },
                      child: Text(
                        "Skip for now",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 16,
                        ),
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