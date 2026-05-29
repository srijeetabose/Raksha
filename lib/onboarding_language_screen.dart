import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:raksha/onboarding_voice_screen.dart';

class OnboardingLanguageScreen extends StatefulWidget {
  const OnboardingLanguageScreen({super.key});
  @override
  State<OnboardingLanguageScreen> createState() => _OnboardingLanguageScreenState();
}

class _OnboardingLanguageScreenState extends State<OnboardingLanguageScreen> {
  String _selectedCode = 'en-IN';
  bool _saving = false;

  static const _languages = [
    {'name': 'English', 'native': 'English', 'code': 'en-IN', 'flag': '🇮🇳'},
    {'name': 'Hindi', 'native': 'हिन्दी', 'code': 'hi-IN', 'flag': '🇮🇳'},
    {'name': 'Bengali', 'native': 'বাংলা', 'code': 'bn-IN', 'flag': '🇮🇳'},
    {'name': 'Tamil', 'native': 'தமிழ்', 'code': 'ta-IN', 'flag': '🇮🇳'},
    {'name': 'Telugu', 'native': 'తెలుగు', 'code': 'te-IN', 'flag': '🇮🇳'},
    {'name': 'Kannada', 'native': 'ಕನ್ನಡ', 'code': 'kn-IN', 'flag': '🇮🇳'},
    {'name': 'Malayalam', 'native': 'മലയാളം', 'code': 'ml-IN', 'flag': '🇮🇳'},
    {'name': 'Marathi', 'native': 'मराठी', 'code': 'mr-IN', 'flag': '🇮🇳'},
    {'name': 'Gujarati', 'native': 'ગુજરાતી', 'code': 'gu-IN', 'flag': '🇮🇳'},
    {'name': 'Punjabi', 'native': 'ਪੰਜਾਬੀ', 'code': 'pa-IN', 'flag': '🇮🇳'},
    {'name': 'Odia', 'native': 'ଓଡ଼ିଆ', 'code': 'or-IN', 'flag': '🇮🇳'},
    {'name': 'Urdu', 'native': 'اردو', 'code': 'ur-IN', 'flag': '🇮🇳'},
  ];

  Future<void> _saveAndContinue() async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'voiceLanguage': _selectedCode,
        }, SetOptions(merge: true));
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingVoiceScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const purpleDark = Color(0xFF6A5AE3);
    const purpleLight = Color(0xFF936EE4);

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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('🌐', style: TextStyle(fontSize: 40)),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Choose Your Language',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Voice detection will work in your chosen language',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _languages.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final lang = _languages[index];
                      final isSelected = _selectedCode == lang['code'];
                      return ListTile(
                        onTap: () => setState(() => _selectedCode = lang['code']!),
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: purpleDark.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.language, color: purpleDark, size: 20),
                        ),
                        title: Text(
                          lang['native']!,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? purpleDark : Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(lang['name']!,
                            style: TextStyle(color: Colors.grey[600])),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: purpleDark)
                            : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tileColor: isSelected ? purpleDark.withOpacity(0.05) : null,
                      );
                    },
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: purpleDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _saving
                        ? const CircularProgressIndicator(color: purpleDark)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Continue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
