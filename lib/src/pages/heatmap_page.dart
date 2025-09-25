import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// HeatmapPage
/// - Requests location permission
/// - Centers map on user
/// - Fits camera to a 10 km radius circle
/// - Draws the 10 km boundary
/// - Shows an "Area Safety Score" chip
class HeatmapPage extends StatefulWidget {
  const HeatmapPage({super.key});

  @override
  State<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends State<HeatmapPage> {
  final MapController _mapController = MapController();

  LatLng? _center;
  final double _radiusMeters = 10000; // 10 km
  int? _safetyScore;

  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var perm = await Geolocator.checkPermission();

      if (!serviceEnabled) {
        setState(() {
          _denied = true;
          _loading = false;
        });
        return;
      }

      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _denied = true;
          _loading = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final c = LatLng(pos.latitude, pos.longitude);
      final score = _estimateSafetyScore(c);

      setState(() {
        _center = c;
        _safetyScore = score;
        _loading = false;
      });

      // Fit camera to the 10 km radius after the first frame.
      await Future.delayed(const Duration(milliseconds: 50));
      _fitToRadius(c, _radiusMeters);
    } catch (_) {
      setState(() {
        _denied = true;
        _loading = false;
      });
    }
  }

  /// Approximates a bounding box for [meters] around [c] and fits the camera.
  void _fitToRadius(LatLng c, double meters) {
    final dLat = meters / 111320.0;
    final dLng = meters / (111320.0 * math.cos(c.latitude * math.pi / 180.0));
    final sw = LatLng(c.latitude - dLat, c.longitude - dLng);
    final ne = LatLng(c.latitude + dLat, c.longitude + dLng);
    final bounds = LatLngBounds(sw, ne);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)),
    );
  }

  /// Generates a polygon approximating a circle of [meters] around [c].
  List<LatLng> _circlePoly(LatLng c, double meters, {int steps = 180}) {
    final res = <LatLng>[];
    const earthRadius = 6371000.0;
    final angDist = meters / earthRadius;
    final lat1 = c.latitude * math.pi / 180.0;
    final lon1 = c.longitude * math.pi / 180.0;

    for (int i = 0; i <= steps; i++) {
      final brng = (i * (360 / steps)) * math.pi / 180.0;
      final lat2 = math.asin(math.sin(lat1) * math.cos(angDist) +
          math.cos(lat1) * math.sin(angDist) * math.cos(brng));
      final lon2 = lon1 +
          math.atan2(
              math.sin(brng) * math.sin(angDist) * math.cos(lat1),
              math.cos(angDist) - math.sin(lat1) * math.sin(lat2));
      res.add(LatLng(lat2 * 180.0 / math.pi, lon2 * 180.0 / math.pi));
    }
    return res;
  }

  /// Temporary deterministic placeholder based on coords.
  int _estimateSafetyScore(LatLng c) {
    final val =
        (((c.latitude.abs() * 13.7) + (c.longitude.abs() * 7.3)) % 100).round();
    return val.clamp(30, 95);
  }

  @override
  Widget build(BuildContext context) {
    final center = _center ?? const LatLng(20.5937, 78.9629); // India fallback

    return Scaffold(
      appBar: AppBar(title: const Text('Heatmap')),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_denied)
            _LocationDenied(
              onOpenSettings: () => Geolocator.openAppSettings(),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 12,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'toursecure',
                ),
                PolygonLayer(
                  polygons: [
                    if (_center != null)
                      Polygon(
                        points: _circlePoly(center, _radiusMeters),
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.12),
                        borderColor: Theme.of(context).colorScheme.primary,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (_center != null)
                      Marker(
                        point: center,
                        width: 40,
                        height: 40,
                        child: const _CenterMarker(),
                      ),
                  ],
                ),
              ],
            ),

          // Score chip/card overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _ScoreCard(score: _safetyScore),
          ),
        ],
      ),

      // Handy recenter control
      floatingActionButton: _center == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _fitToRadius(center, _radiusMeters),
              label: const Text('Fit 10 km'),
              icon: const Icon(Icons.center_focus_strong),
            ),
    );
  }
}

class _CenterMarker extends StatelessWidget {
  const _CenterMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E88E5),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.my_location, color: Colors.white, size: 20),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final int? score;
  const _ScoreCard({this.score});

  @override
  Widget build(BuildContext context) {
    final s = score ?? 0;
    Color color;
    if (s >= 75) {
      color = Colors.green;
    } else if (s >= 50) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.shield),
            const SizedBox(width: 10),
            const Text(
              'Area Safety Score',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Text(
                '${score ?? '--'} / 100',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationDenied extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _LocationDenied({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.location_off, size: 48),
        const SizedBox(height: 10),
        const Text('Location permission needed'),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: onOpenSettings,
          child: const Text('Open Settings'),
        ),
      ]),
    );
  }
}
