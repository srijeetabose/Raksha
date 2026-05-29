import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class SafetyMapScreen extends StatefulWidget {
  const SafetyMapScreen({super.key});
  @override
  State<SafetyMapScreen> createState() => _SafetyMapScreenState();
}

class _SafetyMapScreenState extends State<SafetyMapScreen> {
  final MapController _mapController = MapController();
  Position? _userPosition;
  List<_Place> _places = [];
  bool _loading = false;
  String _selectedCategory = '';

  static const _categories = [
    {
      'label': 'Hospital',
      'icon': Icons.local_hospital,
      'color': Color(0xFFE53935),
      'tag': 'amenity=hospital',
    },
    {
      'label': 'Police',
      'icon': Icons.local_police,
      'color': Color(0xFF1565C0),
      'tag': 'amenity=police',
    },
    {
      'label': 'Pharmacy',
      'icon': Icons.medication,
      'color': Color(0xFF2E7D32),
      'tag': 'amenity=pharmacy',
    },
  ];

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    setState(() => _loading = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _userPosition = pos);
      _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
    } catch (e) {
      debugPrint('Location error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPlaces(String tag, String label) async {
    if (_userPosition == null) {
      await _getUserLocation();
      if (_userPosition == null) return;
    }

    setState(() { _loading = true; _selectedCategory = label; _places = []; });

    final lat = _userPosition!.latitude;
    final lon = _userPosition!.longitude;

    // Overpass QL query
    final query = '''
[out:json][timeout:25];
(
  node[$tag](around:5000,$lat,$lon);
  way[$tag](around:5000,$lat,$lon);
);
out center 30;
''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;
        final places = <_Place>[];

        for (final e in elements) {
          final pLat = (e['lat'] ?? e['center']?['lat'])?.toDouble();
          final pLon = (e['lon'] ?? e['center']?['lon'])?.toDouble();
          if (pLat == null || pLon == null) continue;

          final tags = e['tags'] as Map<String, dynamic>? ?? {};
          final name = (tags['name'] ?? tags['name:en'] ?? label).toString();
          final openingHours = tags['opening_hours'] as String?;
          final phone = tags['phone'] ?? tags['contact:phone'];

          places.add(_Place(
            name: name,
            lat: pLat,
            lon: pLon,
            category: label,
            openingHours: openingHours,
            phone: phone?.toString(),
          ));
        }

        // Sort by distance from user
        places.sort((a, b) {
          final da = Geolocator.distanceBetween(lat, lon, a.lat, a.lon);
          final db = Geolocator.distanceBetween(lat, lon, b.lat, b.lon);
          return da.compareTo(db);
        });

        setState(() => _places = places.take(20).toList());

        if (places.isNotEmpty) {
          _mapController.move(LatLng(lat, lon), 14);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No $label found within 5km')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load places. Check internet connection.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDirections(_Place place) {
    const channel = MethodChannel('com.raksha/sos_service');
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lon}&travelmode=driving';
    channel.invokeMethod('openUrl', {'url': url});
  }

  Color _categoryColor(String label) {
    final cat = _categories.firstWhere((c) => c['label'] == label, orElse: () => _categories[0]);
    return cat['color'] as Color;
  }

  IconData _categoryIcon(String label) {
    final cat = _categories.firstWhere((c) => c['label'] == label, orElse: () => _categories[0]);
    return cat['icon'] as IconData;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toInt()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  void _showPlaceDetails(_Place place) {
    final dist = _userPosition != null
        ? Geolocator.distanceBetween(_userPosition!.latitude, _userPosition!.longitude, place.lat, place.lon)
        : null;

    // Simple open/closed check based on opening hours
    String openStatus = 'Hours not available';
    Color statusColor = Colors.grey;
    if (place.openingHours != null) {
      openStatus = place.openingHours!;
      statusColor = Colors.blue;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _categoryColor(place.category).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_categoryIcon(place.category),
                      color: _categoryColor(place.category), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(place.category,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (dist != null)
              Row(
                children: [
                  const Icon(Icons.directions_walk, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(_formatDistance(dist),
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(openStatus,
                      style: TextStyle(color: statusColor, fontSize: 13)),
                ),
              ],
            ),
            if (place.phone != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.phone, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(place.phone!, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openDirections(place);
                },
                icon: const Icon(Icons.directions),
                label: const Text('Get Directions in Google Maps'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _categoryColor(place.category),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLatLng = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : const LatLng(20.5937, 78.9629);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Map'),
        backgroundColor: const Color(0xFF6A5AE3),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Category buttons
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: _categories.map((cat) {
                final label = cat['label'] as String;
                final isSelected = _selectedCategory == label;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => _fetchPlaces(cat['tag'] as String, label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cat['color'] as Color
                              : (cat['color'] as Color).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cat['color'] as Color),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cat['icon'] as IconData,
                                size: 22,
                                color: isSelected ? Colors.white : cat['color'] as Color),
                            const SizedBox(height: 4),
                            Text(label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : cat['color'] as Color,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Map
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: userLatLng, initialZoom: 14),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.raksha',
                    ),
                    MarkerLayer(markers: [
                      // User location marker
                      if (_userPosition != null)
                        Marker(
                          point: userLatLng,
                          width: 48,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A5AE3),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                            ),
                            child: const Icon(Icons.my_location, color: Colors.white, size: 22),
                          ),
                        ),
                      // Place markers
                      ..._places.map((place) => Marker(
                        point: LatLng(place.lat, place.lon),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _showPlaceDetails(place),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _categoryColor(place.category),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: Icon(_categoryIcon(place.category),
                                color: Colors.white, size: 22),
                          ),
                        ),
                      )),
                    ]),
                  ],
                ),

                if (_loading)
                  Container(
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6A5AE3)),
                    ),
                  ),

                // Results count
                if (_places.isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_places.length} ${_selectedCategory}s nearby — tap to view',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),

                // My location button
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    onPressed: () {
                      if (_userPosition != null) {
                        _mapController.move(userLatLng, 14);
                      } else {
                        _getUserLocation();
                      }
                    },
                    child: const Icon(Icons.my_location, color: Color(0xFF6A5AE3)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Place {
  final String name;
  final double lat;
  final double lon;
  final String category;
  final String? openingHours;
  final String? phone;

  const _Place({
    required this.name,
    required this.lat,
    required this.lon,
    required this.category,
    this.openingHours,
    this.phone,
  });
}
