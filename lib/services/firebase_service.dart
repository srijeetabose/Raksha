// lib/services/firebase_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID
  static String? get currentUserId => _auth.currentUser?.uid;

  // --- SOS Alert Management ---
  
  /// Creates a new SOS alert in Firestore
  static Future<String?> createSosAlert({
    required Position location,
    required String userName,
    List<String>? emergencyContacts,
  }) async {
    try {
      final alertData = {
        'userId': currentUserId,
        'userName': userName,
        'location': GeoPoint(location.latitude, location.longitude),
        'initialTimestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        'emergencyContacts': emergencyContacts ?? [],
        'alertType': 'gesture_voice_trigger',
        'deviceInfo': {
          'accuracy': location.accuracy,
          'altitude': location.altitude,
          'speed': location.speed,
        }
      };

      final docRef = await _firestore.collection('sos_alerts').add(alertData);
      print('SOS Alert created with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error creating SOS alert: $e');
      return null;
    }
  }

  /// Updates SOS alert location during active emergency
  static Future<void> updateSosLocation(String alertId, Position location) async {
    try {
      await _firestore.collection('sos_alerts').doc(alertId).update({
        'location': GeoPoint(location.latitude, location.longitude),
        'lastLocationUpdate': FieldValue.serverTimestamp(),
        'locationHistory': FieldValue.arrayUnion([
          {
            'location': GeoPoint(location.latitude, location.longitude),
            'timestamp': FieldValue.serverTimestamp(),
            'accuracy': location.accuracy,
          }
        ])
      });
    } catch (e) {
      print('Error updating SOS location: $e');
    }
  }

  /// Marks SOS alert as safe
  static Future<void> markSosAsSafe(String alertId) async {
    try {
      await _firestore.collection('sos_alerts').doc(alertId).update({
        'status': 'safe',
        'safeTimestamp': FieldValue.serverTimestamp(),
      });
      print('SOS Alert marked as safe: $alertId');
    } catch (e) {
      print('Error marking SOS as safe: $e');
    }
  }

  /// Gets active SOS alerts for current user
  static Future<List<DocumentSnapshot>> getActiveSosAlerts() async {
    try {
      final query = await _firestore
          .collection('sos_alerts')
          .where('userId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'active')
          .orderBy('initialTimestamp', descending: true)
          .get();
      
      return query.docs;
    } catch (e) {
      print('Error getting active SOS alerts: $e');
      return [];
    }
  }

  // --- User Settings Management ---

  /// Updates user settings in Firestore
  static Future<bool> updateUserSettings(Map<String, dynamic> settings) async {
    try {
      if (currentUserId == null) return false;
      
      await _firestore.collection('users').doc(currentUserId).update({
        ...settings,
        'lastSettingsUpdate': FieldValue.serverTimestamp(),
      });
      
      return true;
    } catch (e) {
      print('Error updating user settings: $e');
      return false;
    }
  }

  /// Gets user settings from Firestore
  static Future<Map<String, dynamic>?> getUserSettings() async {
    try {
      if (currentUserId == null) return null;
      
      final doc = await _firestore.collection('users').doc(currentUserId).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      print('Error getting user settings: $e');
      return null;
    }
  }

  // --- Emergency Contacts Management ---

  /// Updates emergency contacts
  static Future<bool> updateEmergencyContacts(List<Map<String, String>> contacts) async {
    try {
      return await updateUserSettings({
        'emergencyContacts': contacts,
        'contactsLastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating emergency contacts: $e');
      return false;
    }
  }

  /// Gets emergency contacts
  static Future<List<Map<String, String>>> getEmergencyContacts() async {
    try {
      final settings = await getUserSettings();
      if (settings == null) return [];
      
      final contacts = settings['emergencyContacts'] as List<dynamic>?;
      return contacts?.cast<Map<String, dynamic>>()
          .map((contact) => contact.cast<String, String>())
          .toList() ?? [];
    } catch (e) {
      print('Error getting emergency contacts: $e');
      return [];
    }
  }

  // --- Voice and Gesture Triggers ---

  /// Updates voice trigger words
  static Future<bool> updateVoiceTriggers(List<String> words) async {
    try {
      return await updateUserSettings({
        'triggerVoiceWords': words,
        'isVoiceDetectionEnabled': words.isNotEmpty,
        'voiceTriggersLastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating voice triggers: $e');
      return false;
    }
  }

  /// Updates gesture triggers
  static Future<bool> updateGestureTriggers(List<String> gestures) async {
    try {
      return await updateUserSettings({
        'triggerGestures': gestures,
        'isGestureDetectionEnabled': gestures.isNotEmpty,
        'gestureTriggersLastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating gesture triggers: $e');
      return false;
    }
  }

  // --- Police Integration ---

  /// Notifies nearby police stations
  static Future<void> notifyPolice({
    required Position location,
    required String alertId,
    required String userName,
  }) async {
    try {
      // Create police notification
      await _firestore.collection('police_notifications').add({
        'alertId': alertId,
        'userId': currentUserId,
        'userName': userName,
        'location': GeoPoint(location.latitude, location.longitude),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'priority': 'high',
        'alertType': 'emergency_sos',
      });

      print('Police notification sent for alert: $alertId');
    } catch (e) {
      print('Error notifying police: $e');
    }
  }

  // --- Analytics and Logging ---

  /// Logs app usage for analytics
  static Future<void> logEvent(String eventName, Map<String, dynamic> parameters) async {
    try {
      await _firestore.collection('app_analytics').add({
        'userId': currentUserId,
        'eventName': eventName,
        'parameters': parameters,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error logging event: $e');
    }
  }

  /// Logs SOS trigger events
  static Future<void> logSosTrigger({
    required String triggerType, // 'gesture', 'voice', 'manual'
    required String triggerValue, // specific gesture or voice word
  }) async {
    try {
      await logEvent('sos_triggered', {
        'triggerType': triggerType,
        'triggerValue': triggerValue,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error logging SOS trigger: $e');
    }
  }

  // --- Real-time Listeners ---

  /// Stream of active SOS alerts for current user
  static Stream<QuerySnapshot> activeSosAlertsStream() {
    return _firestore
        .collection('sos_alerts')
        .where('userId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'active')
        .orderBy('initialTimestamp', descending: true)
        .snapshots();
  }

  /// Stream of user settings changes
  static Stream<DocumentSnapshot> userSettingsStream() {
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .snapshots();
  }
}