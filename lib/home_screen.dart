// lib/home_screen.dart
// This file acts as the main Router/Wrapper for the Home Dashboard.

import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import 'package:raksha/user_safety_dashboard.dart';
import 'package:raksha/gestures_tab.dart';
import 'package:raksha/safety_map_screen.dart';
import 'package:raksha/contacts_tab.dart';
import 'package:raksha/settings_tab.dart';

enum AppMode { user, police }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppMode _currentMode = AppMode.user;
  bool _isPoliceVerified = false;
  bool _isLoading = true;
  int _currentTabIndex = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _startBackgroundServices();
  }

  Future<void> _startBackgroundServices() async {
    await Future.delayed(const Duration(seconds: 2));
    try {
      const platform = MethodChannel('com.example.raksha/gesture_service');
      await platform.invokeMethod('startRealBackgroundService', {
        'gestures': ['Thumb_Up', 'Victory', 'Closed_Fist'],
        'crossApp': true,
      });
      await Future.delayed(const Duration(milliseconds: 500));
      await platform.invokeMethod('startVoiceDetection', {
        'triggers': ['help me', 'emergency', 'call police'],
      });
    } catch (e) {
      print("❌ Error starting background services: $e");
    }
  }

  Future<void> _checkUserRole() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final verificationDoc =
          await _firestore.collection('police_verification').doc(userId).get();
      if (verificationDoc.exists) {
        final status = verificationDoc.data()?['verificationStatus'] as String?;
        if (status == 'approved') {
          _isPoliceVerified = true;
          _currentMode = AppMode.police;
        }
      }
    } catch (e) {
      print("Error checking police role: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildCurrentDashboard() {
    if (_isPoliceVerified && _currentMode == AppMode.police) {
      return const PoliceAlertsDashboard();
    }
    switch (_currentTabIndex) {
      case 0:
        return const UserSafetyDashboard();
      case 1:
        return const GesturesTab();
      case 2:
        return const ContactsTab();
      case 3:
        return const SettingsTab();
      case 4:
        return const SafetyMapScreen();
      default:
        return const UserSafetyDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6A5AE3))),
      );
    }
    if (_isPoliceVerified) {
      final userId = _auth.currentUser!.uid;
      return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('police_verification').doc(userId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(
                    child: CircularProgressIndicator(color: Color(0xFF6A5AE3))));
          }
          if (snapshot.hasData &&
              snapshot.data!['verificationStatus'] == 'pending') {
            return const PolicePendingScreen();
          }
          return _buildScaffold(context);
        },
      );
    }
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    const Color purpleDark = Color(0xFF6A5AE3);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raksha',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: purpleDark,
        elevation: 0,
        actions: [
          if (_isPoliceVerified)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => setState(() {
                _currentMode =
                    _currentMode == AppMode.user ? AppMode.police : AppMode.user;
              }),
              icon: Icon(_currentMode == AppMode.user
                  ? Icons.security
                  : Icons.person),
              label: Text(
                  _currentMode == AppMode.user ? 'POLICE MODE' : 'USER MODE'),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _auth.signOut(),
          ),
        ],
      ),
      body: _buildCurrentDashboard(),
      bottomNavigationBar: _currentMode == AppMode.user
          ? BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.back_hand), label: 'Gestures'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.contacts), label: 'Contacts'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.settings), label: 'Settings'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.map), label: 'Safety Map'),
              ],
              selectedItemColor: purpleDark,
              unselectedItemColor: Colors.grey,
              currentIndex: _currentTabIndex,
              onTap: (index) => setState(() => _currentTabIndex = index),
            )
          : null,
    );
  }
}

// =========================================================================

class PolicePendingScreen extends StatelessWidget {
  const PolicePendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_clock, size: 64, color: Colors.amber),
              SizedBox(height: 20),
              Text('Verification Pending',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              SizedBox(height: 10),
              Text(
                "Your account is under manual review. You will receive an update once your verification status is 'approved' or 'rejected'.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// Police Alerts Dashboard — Live SOS feed with map view
// =========================================================================

class PoliceAlertsDashboard extends StatefulWidget {
  const PoliceAlertsDashboard({super.key});

  @override
  State<PoliceAlertsDashboard> createState() => _PoliceAlertsDashboardState();
}

class _PoliceAlertsDashboardState extends State<PoliceAlertsDashboard> {
  static const Color _purple = Color(0xFF6A5AE3);
  static const double _radiusKm = 20.0;

  bool _isPoliceActive = false;
  bool _isLoading = true;
  Position? _policePosition;
  StreamSubscription<Position>? _locationSub;

  // 0 = list view, 1 = map view
  int _viewTab = 0;
  final MapController _mapController = MapController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadPoliceStatus();
    await _startLocationTracking();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadPoliceStatus() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && mounted) {
        setState(
            () => _isPoliceActive = doc.data()?['isPoliceActive'] ?? false);
      }
    } catch (_) {}
  }

  Future<void> _startLocationTracking() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() => _policePosition = pos);

      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 50),
      ).listen((p) {
        if (mounted) setState(() => _policePosition = p);
      });
    } catch (_) {}
  }

  Future<void> _togglePoliceStatus(bool newValue) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    setState(() => _isPoliceActive = newValue);
    try {
      await _firestore.collection('users').doc(userId).update({
        'isPoliceActive': newValue,
        'lastStatusChange': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newValue
              ? '✅ You are now Active — receiving alerts'
              : '🔴 You are now Inactive'),
          backgroundColor: newValue ? Colors.green : Colors.red,
        ));
      }
    } catch (_) {
      setState(() => _isPoliceActive = !newValue);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update status.')));
      }
    }
  }

  double _distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * pi / 180;

  List<QueryDocumentSnapshot> _filterNearby(
      List<QueryDocumentSnapshot> docs) {
    if (_policePosition == null) return docs;
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final loc = data['currentLocation'] as Map<String, dynamic>?;
      if (loc == null) return false;
      final lat = (loc['latitude'] as num?)?.toDouble();
      final lon = (loc['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return false;
      return _distanceKm(_policePosition!.latitude,
              _policePosition!.longitude, lat, lon) <=
          _radiusKm;
    }).toList();
  }

  Future<void> _respondToAlert(
      String sessionId, Map<String, dynamic> data) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _firestore
        .collection('emergency_sessions')
        .doc(sessionId)
        .update({
      'respondingOfficerId': userId,
      'respondingAt': FieldValue.serverTimestamp(),
      'status': 'officer_responding',
    });

    final loc = data['currentLocation'] as Map<String, dynamic>?;
    final lat = (loc?['latitude'] as num?)?.toDouble();
    final lon = (loc?['longitude'] as num?)?.toDouble();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🚨 Responding to Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You are now marked as responding.',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (lat != null && lon != null) ...[
              Text('Victim location:\n${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'),
              const SizedBox(height: 4),
              const Text('Tap "Copy Maps Link" to navigate.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          if (lat != null && lon != null)
            TextButton.icon(
              icon: const Icon(Icons.map, color: _purple),
              label: const Text('Copy Maps Link',
                  style: TextStyle(color: _purple)),
              onPressed: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(
                    text: 'https://maps.google.com/?q=$lat,$lon'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Maps link copied to clipboard')));
              },
            ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: _purple),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _dismissAlert(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dismiss Alert?'),
        content:
            const Text('Mark this alert as resolved / false alarm?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dismiss',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _firestore
          .collection('emergency_sessions')
          .doc(sessionId)
          .update({
        'isActive': false,
        'dismissedBy': _auth.currentUser?.uid,
        'dismissedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  String _timeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    DateTime dt;
    if (timestamp is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      try {
        dt = (timestamp as dynamic).toDate() as DateTime;
      } catch (_) {
        return 'Unknown';
      }
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _purple));
    }

    return Column(
      children: [
        // Active/Inactive status bar
        Container(
          color: _isPoliceActive ? Colors.green[700] : Colors.grey[700],
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                _isPoliceActive ? Icons.shield : Icons.shield_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isPoliceActive
                      ? 'ACTIVE — Receiving alerts within ${_radiusKm.toInt()}km'
                      : 'INACTIVE — Go active to receive SOS alerts',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              Switch(
                value: _isPoliceActive,
                onChanged: _togglePoliceStatus,
                activeColor: Colors.white,
                activeTrackColor: Colors.green[300],
              ),
            ],
          ),
        ),

        if (_isPoliceActive) ...[
          // List / Map toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.list),
                    label: Text('Alert List')),
                ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.map),
                    label: Text('Map View')),
              ],
              selected: {_viewTab},
              onSelectionChanged: (s) =>
                  setState(() => _viewTab = s.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? _purple
                      : null,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.white
                      : _purple,
                ),
              ),
            ),
          ),

          // Live Firestore stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('emergency_sessions')
                  .where('isActive', isEqualTo: true)
                  .orderBy('startTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: _purple));
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}'));
                }

                final allDocs = snapshot.data?.docs ?? [];
                final nearbyDocs = _filterNearby(allDocs);

                if (nearbyDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 64, color: Colors.green[400]),
                        const SizedBox(height: 16),
                        const Text('No active SOS alerts nearby',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(
                            'Monitoring ${_radiusKm.toInt()}km radius',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return _viewTab == 0
                    ? _buildAlertList(nearbyDocs)
                    : _buildMapView(nearbyDocs);
              },
            ),
          ),
        ] else ...[
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off,
                      size: 72, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'Go Active to receive\nSOS alerts near you',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _togglePoliceStatus(true),
                    icon: const Icon(Icons.shield, color: Colors.white),
                    label: const Text('Go Active',
                        style: TextStyle(
                            color: Colors.white, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAlertList(List<QueryDocumentSnapshot> docs) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        final data = doc.data() as Map<String, dynamic>;
        final loc = data['currentLocation'] as Map<String, dynamic>?;
        final lat = (loc?['latitude'] as num?)?.toDouble();
        final lon = (loc?['longitude'] as num?)?.toDouble();
        final isResponding = data['respondingOfficerId'] != null;
        final startTime = data['startTime'];

        double? distKm;
        if (_policePosition != null && lat != null && lon != null) {
          distKm = _distanceKm(_policePosition!.latitude,
              _policePosition!.longitude, lat, lon);
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isResponding ? Colors.orange : Colors.red,
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isResponding ? Colors.orange : Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isResponding ? '🚔 RESPONDING' : '🚨 SOS ACTIVE',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    Text(_timeAgo(startTime),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                if (lat != null && lon != null)
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.red, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (distKm != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${distKm.toStringAsFixed(1)} km away)',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isResponding
                            ? null
                            : () => _respondToAlert(doc.id, data),
                        icon: const Icon(Icons.directions_car, size: 16),
                        label: Text(
                            isResponding ? 'Responding' : 'Respond'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _purple,
                          side: const BorderSide(color: _purple),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _dismissAlert(doc.id),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Dismiss'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapView(List<QueryDocumentSnapshot> docs) {
    final center = _policePosition != null
        ? LatLng(_policePosition!.latitude, _policePosition!.longitude)
        : const LatLng(28.7041, 77.1025);

    final alertMarkers = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final loc = data['currentLocation'] as Map<String, dynamic>?;
      final lat = (loc?['latitude'] as num?)?.toDouble();
      final lon = (loc?['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      final isResponding = data['respondingOfficerId'] != null;

      return Marker(
        point: LatLng(lat, lon),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _respondToAlert(doc.id, data),
          child: Container(
            decoration: BoxDecoration(
              color: isResponding ? Colors.orange : Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4)
              ],
            ),
            child: const Icon(Icons.sos, color: Colors.white, size: 22),
          ),
        ),
      );
    }).whereType<Marker>().toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.raksha',
        ),
        // 20km radius circle
        CircleLayer(
          circles: _policePosition != null
              ? [
                  CircleMarker(
                    point: center,
                    radius: _radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: const Color(0xFF6A5AE3).withOpacity(0.08),
                    borderColor: const Color(0xFF6A5AE3).withOpacity(0.4),
                    borderStrokeWidth: 1.5,
                  ),
                ]
              : [],
        ),
        // Officer position (purple shield)
        if (_policePosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 44,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A5AE3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.shield,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        // SOS alert markers (red/orange)
        MarkerLayer(markers: alertMarkers),
      ],
    );
  }
}
