// lib/contacts_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class EmergencyContact {
  String name;
  String phone;
  EmergencyContact({required this.name, required this.phone});

  // Convert to Map for Firestore storage
  Map<String, String> toMap() => {'name': name, 'phone': phone};

  // Convert from Firestore Map
  static EmergencyContact fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      name: map['name'] ?? 'Unknown',
      phone: map['phone'] ?? '',
    );
  }
}

class _ContactsTabState extends State<ContactsTab> {
  static const int maxContacts = 5;
  List<EmergencyContact> _contactList = [];
  bool _isLoading = true;
  final _firestore = FirebaseFirestore.instance;
  final _userId = FirebaseAuth.instance.currentUser?.uid;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadContactsFromFirestore();
  }

  // --- Data Loading ---
  Future<void> _loadContactsFromFirestore() async {
    if (_userId == null) return;
    setState(() => _isLoading = true);

    try {
      final doc = await _firestore.collection('users').doc(_userId).get();
      if (doc.exists && doc.data() != null && doc.data()!['emergencyContacts'] is List) {
        final List<dynamic> loadedMaps = doc.data()!['emergencyContacts'] as List<dynamic>;
        
        setState(() {
          _contactList = loadedMaps
              .map((map) => EmergencyContact.fromMap(map as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      // Avoid printing in production
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Contact Picker Logic ---
  Future<void> _openContactPicker() async {
    if (_contactList.length >= maxContacts) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Maximum limit of 5 contacts reached.")));
      return;
    }

    try {
      // Try to open contact picker directly first
      final Contact? contact = await FlutterContacts.openExternalPick();
      
      if (contact != null) {
        final phone = contact.phones.isNotEmpty ? contact.phones.first.number.replaceAll(RegExp(r'[^0-9+]'), '') : null;
        
        if (phone != null && phone.isNotEmpty) {
          setState(() {
            _contactList.add(EmergencyContact(name: contact.displayName, phone: phone));
          });
          _saveContactsAndContinue(showSnackBar: true); // Auto-save after picking
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contact has no phone number.")));
          }
        }
      }
    } catch (e) {
      print("Contact picker error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to access contacts: ${e.toString()}")));
      }
    }
  }

  // --- Save Logic ---
  Future<void> _saveContactsAndContinue({bool showSnackBar = false}) async {
    if (_userId == null || _isLoading) return;

    // Check if any contact is incomplete
    if (_contactList.any((c) => c.name.isEmpty || c.phone.isEmpty)) {
        if (showSnackBar) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please ensure all contacts have a name and phone number.")));
        return;
    }

    if (_contactList.isEmpty) {
        if (showSnackBar) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please add at least one emergency contact.")));
        return;
    }

    setState(() => _isLoading = true);
    
    final List<Map<String, String>> finalMaps = _contactList.map((c) => c.toMap()).toList();

    try {
      await _firestore.collection('users').doc(_userId).update({
        'emergencyContacts': finalMaps,
      });

      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Emergency contacts saved!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error saving contacts to cloud.")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI Update Logic (Handles Delete) ---
  void _deleteContact(int index) {
    setState(() {
      _contactList.removeAt(index);
    });
    _saveContactsAndContinue(); // Auto-save after deleting
  }
  
  // Helper Widget for the message preview section
  Widget _buildMessagePreview() {
    const Color purpleDark = Color(0xFF6A5AE3); 

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preview Box
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEAF9), 
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("🚨 EMERGENCY ALERT from [Name]", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              SizedBox(height: 8),
              Text("📍 Current location: [Location]", style: TextStyle(color: Colors.black54)),
              Text("🔗 Live location: [Link]", style: TextStyle(color: Colors.black54)),
              SizedBox(height: 8),
              Text("Please respond immediately! This is an automated Raksha safety alert.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black54)),
            ],
          ),
        ),
        
        // Auto-Send Information Card
        Card(
          margin: const EdgeInsets.only(top: 16),
          color: Colors.white, 
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Auto-Send Information", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                const Divider(),
                _buildAutoSendItem("Messages are sent AUTOMATICALLY after 17-second window.", purpleDark),
                _buildAutoSendItem("All emergency contacts will receive the message.", purpleDark),
                _buildAutoSendItem("Nearby police stations are notified simultaneously.", purpleDark),
                _buildAutoSendItem("Your live location is shared in real-time.", purpleDark),
                _buildAutoSendItem("Camera and voice recording starts automatically.", purpleDark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoSendItem(String text, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 8, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color purpleDark = Color(0xFF6A5AE3);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Title and Add Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Emergency Contacts", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text("${_contactList.length}/$maxContacts contacts", style: const TextStyle(color: purpleDark, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            const Text("Select up to 5 contacts for immediate alerts.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            
            // Add Contact Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _openContactPicker,
                icon: const Icon(Icons.add),
                label: const Text("Add from Phone Contacts"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: purpleDark,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Contact List Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator()))
                    : _contactList.isEmpty
                        ? const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("No contacts added yet. Tap Add from Phone Contacts.")))
                        : Column(
                            children: List.generate(_contactList.length, (index) {
                              final contact = _contactList[index];
                              return ListTile(
                                leading: const Icon(Icons.person, color: purpleDark),
                                title: TextFormField(
                                  initialValue: contact.name,
                                  decoration: const InputDecoration(hintText: "Name", border: InputBorder.none),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  onChanged: (value) => contact.name = value,
                                ),
                                subtitle: TextFormField(
                                  initialValue: contact.phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(hintText: "Phone", border: InputBorder.none),
                                  onChanged: (value) => contact.phone = value,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteContact(index),
                                ),
                              );
                            }),
                          ),
              ),
            ),
            const SizedBox(height: 32),

            // Emergency Message Preview Section
            const Text("Emergency Message", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            _buildMessagePreview(),
            const SizedBox(height: 32),

            // Save Message Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _saveContactsAndContinue(showSnackBar: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: purpleDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Save Contacts & Update Cloud", style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
      ),
    );
  }
}