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
      'query': '(node["amenity"="hospital"](around:5000,LAT,LON);way["amenity"="hospital"](around:5000,LAT,LON);relation["amenity"="hospital"](around:5000,LAT,LON);)',
    },
    {
      'label': 'Police',
      'icon': Icons.local_police,
      'color': Color(0xFF1565C0),
      'query': '(node["amenity"="police"](around:5000,LAT,LON);way["amenity"="police"](around:5000,LAT,LON);)',
    },
    {
      'label': 'Pharmacy',
      'icon': Icons.medication,
      'color': Color(0xFF2E7D32),
      'query': '(node["amenity"="pharmacy"](around:3000,LAT,LON);way["amenity"="pharmacy"](around:3000,LAT,LON);)',
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

  Future<void> _fetchPlaces(Map<String, dynamic> category) async {
    if (_userPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting your location...')),
      );
      await _getUserLocation();
      if (_userPosition == null) return;
    }

    final label = category['label'] as String;
    setState(() { _loading = true; _selectedCategory = label; _places = []; });

    final lat = _userPosition!.latitude;
    final lon = _userPosition!.longitude;
    final queryTemplate = category['query'] as String;
    final query = '[out:json][timeout:20];\n${queryTemplate.replaceAll('LAT', '$lat').replaceAll('LON', '$lon')}\nout center 30;';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'data=${Uri.encodeComponent(query)}',
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;
        final places = <_Place>[];

        for (final e in elements) {
          final placeLat = (e['lat'] ?? e['center']?['lat'])?.toDouble();
          final placeLon = (e['lon'] ?? e['center']?['lon'])?.toDouble();
          if (placeLat == null || placeLon == null) continue;

          final tags = e['tags'] as Map<String, dynamic>? ?? {};
          final name = tags['name'] ?? tags['name:en'] ?? label;

          places.add(_Place(
            name: name.toString(),
            lat: placeLat,
            lon: placeLon,
            category: label,
          ));
        }

        // Sort by distance
        places.sort((a, b) {
          final da = Geolocator.distanceBetween(lat, lon, a.lat, a.lon);
          final db = Geolocator.distanceBetween(lat, lon, b.lat, b.lon);
          return da.compareTo(db);
        });

        setState(() => _places = places.take(20).toList());

        if (places.isNotEmpty) {
          _mapController.move(LatLng(lat, lon), 13);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No $label found nearby')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading places. Check internet.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDirections(_Place place) {
    // Open Google Maps with exact coordinates
    const channel = MethodChannel('com.raksha/sos_service');
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lon}&travelmode=driving';
    channel.invokeMethod('openUrl', {'url': url}).catchError((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${place.name}: ${place.lat.toStringAsFixed(5)}, ${place.lon.toStringAsFixed(5)}')),
        );
      }
    });
  }

  Color _categoryColor(String label) {
    final cat = _categories.firstWhere((c) => c['label'] == label, orElse: () => _categories[0]);
    return cat['color'] as Color;
  }

  IconData _categoryIcon(String label) {
    final cat = _categories.firstWhere((c) => c['label'] == label, orElse: () => _categories[0]);
    return cat['icon'] as IconData;
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
                      onTap: () => _fetchPlaces(cat as Map<String, dynamic>),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? cat['color'] as Color : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? cat['color'] as Color : Colors.grey[300]!,
                          ),
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
                                  color: isSelected ? Colors.white : Colors.black87,
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
                      if (_userPosition != null)
                        Marker(
                          point: userLatLng,
                          width: 44,
                          height: 44,
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
                      ..._places.map((place) => Marker(
                        point: LatLng(place.lat, place.lon),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _showPlaceSheet(place),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _categoryColor(place.category),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: Icon(_categoryIcon(place.category), color: Colors.white, size: 22),
                          ),
                        ),
                      )),
                    ]),
                  ],
                ),

                if (_loading)
                  Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator(color: Color(0xFF6A5AE3))),
                  ),

                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    onPressed: _getUserLocation,
                    child: const Icon(Icons.my_location, color: Color(0xFF6A5AE3)),
                  ),
                ),

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
                          '${_places.length} ${_selectedCategory}s nearby',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPlaceSheet(_Place place) {
    final dist = _userPosition != null
        ? Geolocator.distanceBetween(
            _userPosition!.latitude, _userPosition!.longitude,
            place.lat, place.lon)
        : null;

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
            if (dist != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.directions_walk, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    dist < 1000
                        ? '${dist.toInt()} m away'
                        : '${(dist / 1000).toStringAsFixed(1)} km away',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
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
}

class _Place {
  final String name;
  final double lat;
  final double lon;
  final String category;
  const _Place({required this.name, required this.lat, required this.lon, required this.category});
}
