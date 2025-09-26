import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_page.dart';

/// HeatmapPage (Population Density around User)
/// - Requests location permission
/// - Prefers a fresh GPS fix (configurable last-known fallback)
/// - Fits camera to a 10 km radius circle (after map is ready)
/// - Draws the 10 km boundary
/// - Tries Supabase `population_cells` for heat; falls back to synthetic heat
/// - Computes "Area Safety Score" from density (lower density => higher score)

class HeatmapPage extends StatefulWidget {
  const HeatmapPage({super.key});

  @override
  State<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends State<HeatmapPage> {
  // Toggle this to allow using last-known if a fresh fix times out.
  static const bool _kAllowLastKnownFallback = false;

  final MapController _mapController = MapController();

  LatLng? _center;
  final double _radiusMeters = 10000; // 10 km
  int? _safetyScore;

  bool _loading = true;

  // Accurate issue flags
  bool _permissionDenied = false;
  bool _serviceDisabled = false;
  String? _locError;

  // Map readiness + pending fit flag
  bool _mapReady = false;
  bool _pendingFit = false;

  // Heat data (population density)
  final _heatRebuild = StreamController<void>.broadcast();
  List<WeightedLatLng> _heatData = const [];

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _heatRebuild.close();
    super.dispose();
  }

  Future<void> _initLocation() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
      _serviceDisabled = false;
      _locError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _serviceDisabled = true;
          _loading = false;
        });
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() {
          _permissionDenied = true;
          _loading = false;
        });
        return;
      }

      // Prefer a fresh, precise fix.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
      } on TimeoutException {
        if (_kAllowLastKnownFallback) {
          pos = await Geolocator.getLastKnownPosition();
        } else {
          rethrow;
        }
      }

      if (pos == null) {
        throw TimeoutException('Could not acquire a current location fix.');
      }

      final c = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = c;
      });

      // Load heat data from Supabase; fallback to synthetic if empty or on error
      await _loadHeatData(c, _radiusMeters);

      setState(() {
        _safetyScore = _estimateSafetyScoreFromDensity(_heatData);
        _loading = false;
        _pendingFit = true; // fit as soon as map is ready
      });

      _maybeFitToRadius(); // in case map is already ready
      _heatRebuild.add(null);
    } on TimeoutException catch (_) {
      setState(() {
        _locError = 'Location timeout. Try again.';
        _loading = false;
      });
    } on LocationServiceDisabledException catch (_) {
      setState(() {
        _serviceDisabled = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _locError = e.toString();
        _loading = false;
      });
    }
  }

  void _maybeFitToRadius() {
    if (_mapReady && _pendingFit && _center != null) {
      _pendingFit = false;
      _fitToRadius(_center!, _radiusMeters);
    }
  }

  Future<void> _loadHeatData(LatLng center, double meters) async {
    try {
      final data = await _fetchHeatDataFromSupabase(center, meters);
      if (data.isNotEmpty) {
        _heatData = data;
      } else {
        _heatData = _buildSyntheticHeat(center, meters);
      }
    } catch (_) {
      _heatData = _buildSyntheticHeat(center, meters);
    }
  }

  /// Pull population density cells within bbox then filter to true circle.
  /// Table: population_cells(centroid_lat, centroid_lng, density_ppkm2)
  Future<List<WeightedLatLng>> _fetchHeatDataFromSupabase(
      LatLng c, double meters) async {
    final client = Supabase.instance.client;

    // Bounding box to reduce payload server-side
    final dLat = meters / 111320.0;
    final dLng = meters / (111320.0 * math.cos(c.latitude * math.pi / 180.0));
    final minLat = c.latitude - dLat;
    final maxLat = c.latitude + dLat;
    final minLng = c.longitude - dLng;
    final maxLng = c.longitude + dLng;

    final rows = await client
        .from('population_cells')
        .select('centroid_lat,centroid_lng,density_ppkm2')
        .gte('centroid_lat', minLat)
        .lte('centroid_lat', maxLat)
        .gte('centroid_lng', minLng)
        .lte('centroid_lng', maxLng);

    if (rows is! List) return const [];

    // Find min/max density for normalization to 0..1
    double minD = double.infinity, maxD = -double.infinity;
    for (final r in rows) {
      final d = (r['density_ppkm2'] as num?)?.toDouble() ?? 0.0;
      if (d < minD) minD = d;
      if (d > maxD) maxD = d;
    }
    if (minD == double.infinity) return const [];
    final range = (maxD - minD).abs() < 1e-9 ? 1.0 : (maxD - minD);

    const earth = 6371000.0;
    final pts = <WeightedLatLng>[];

    for (final r in rows) {
      final lat = (r['centroid_lat'] as num?)?.toDouble();
      final lng = (r['centroid_lng'] as num?)?.toDouble();
      final dens = (r['density_ppkm2'] as num?)?.toDouble() ?? 0.0;
      if (lat == null || lng == null) continue;

      final p = LatLng(lat, lng);

      // keep only points inside the exact circle (not just bbox)
      final dist = _haversineMeters(c, p, earth);
      if (dist > meters) continue;

      // Normalize density to [0,1]; higher density => higher weight (redder)
      final w = ((dens - minD) / range).clamp(0.05, 1.0);
      pts.add(WeightedLatLng(p, w));
    }

    return pts;
  }

  double _haversineMeters(LatLng a, LatLng b, double earthRadius) {
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final sLat1 = math.sin(dLat / 2);
    final sLng1 = math.sin(dLng / 2);
    final aa = sLat1 * sLat1 +
        math.cos(a.latitude * math.pi / 180.0) *
            math.cos(b.latitude * math.pi / 180.0) *
            sLng1 *
            sLng1;
    final c = 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
    return earthRadius * c;
  }

  /// Synthetic fallback if no data / error (visual demo only)
  List<WeightedLatLng> _buildSyntheticHeat(LatLng c, double meters) {
    final pts = <WeightedLatLng>[];
    const samples = 420; // density vs perf
    final rand = math.Random(42);

    for (var i = 0; i < samples; i++) {
      final rUnit = math.pow(rand.nextDouble(), 0.7).toDouble();
      final r = rUnit * meters;
      final theta = rand.nextDouble() * 2 * math.pi;

      const earth = 6371000.0;
      final angDist = r / earth;
      final lat1 = c.latitude * math.pi / 180.0;
      final lon1 = c.longitude * math.pi / 180.0;
      final lat2 = math.asin(math.sin(lat1) * math.cos(angDist) +
          math.cos(lat1) * math.sin(angDist) * math.cos(theta));
      final lon2 = lon1 +
          math.atan2(math.sin(theta) * math.sin(angDist) * math.cos(lat1),
              math.cos(angDist) - math.sin(lat1) * math.sin(lat2));
      final p = LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);

      // weight: stronger near center (just for visual softness)
      final w = (1.0 - rUnit) * 0.9 + rand.nextDouble() * 0.1;
      pts.add(WeightedLatLng(p, w.clamp(0.05, 1.0)));
    }
    return pts;
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

  /// Convert density weights into a "safety" score: sparser => higher score.
  int _estimateSafetyScoreFromDensity(List<WeightedLatLng> pts) {
    if (pts.isEmpty) return 50;
    // Average weight (0..1) where 1 is highest density; invert so sparse = high score
    final avg = pts.map((e) => e.intensity).fold<double>(0.0, (a, b) => a + b) / pts.length;
    final score = ((1.0 - avg) * 100).round();
    return score.clamp(1, 99);
  }

  @override
  Widget build(BuildContext context) {
    // No arbitrary fallback position; show map only when we have a center.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heatmap'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomePage()),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_permissionDenied || _serviceDisabled || _locError != null)
            _LocationIssue(
              permissionDenied: _permissionDenied,
              serviceDisabled: _serviceDisabled,
              errorText: _locError,
              onOpenAppSettings: () => Geolocator.openAppSettings(),
              onOpenLocationSettings: () => Geolocator.openLocationSettings(),
              onRetry: _initLocation,
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center!,
                initialZoom: 12,
                onMapReady: () {
                  _mapReady = true;
                  _maybeFitToRadius();
                },
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                // Base map tiles
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'toursecure',
                ),

                // Heat overlay (Supabase or synthetic)
                HeatMapLayer(
                  heatMapDataSource: InMemoryHeatMapDataSource(
                    data: _heatData,
                  ),
                  heatMapOptions: HeatMapOptions(
                    gradient: {
                      0.0: Colors.green,
                      0.5: Colors.yellow,
                      1.0: Colors.red,
                    },
                    radius: 35,
                    blurFactor: 0.5,   // replaces 'blur'
                    minOpacity: 0.15,
                    layerOpacity: 0.95, // replaces 'maxOpacity'
                  ),
                  reset: _heatRebuild.stream,
                ),

                // Circle boundary (10 km)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _circlePoly(_center!, _radiusMeters),
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                      borderColor: Theme.of(context).colorScheme.primary,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

                // Current location marker
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _center!,
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
      floatingActionButton: (_center == null || !_mapReady)
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                _pendingFit = true;
                _maybeFitToRadius();
              },
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
            const Icon(Icons.group), // population-ish icon
            const SizedBox(width: 10),
            const Text(
              'Area Safety Score',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

class _LocationIssue extends StatelessWidget {
  final bool permissionDenied;
  final bool serviceDisabled;
  final String? errorText;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onRetry;

  const _LocationIssue({
    required this.permissionDenied,
    required this.serviceDisabled,
    required this.errorText,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    String title;
    List<Widget> actions = [];

    if (serviceDisabled) {
      title = 'Location services are OFF';
      actions.addAll([
        FilledButton(
          onPressed: onOpenLocationSettings,
          child: const Text('Open Location Settings'),
        ),
      ]);
    } else if (permissionDenied) {
      title = 'Location permission needed';
      actions.addAll([
        FilledButton(
          onPressed: onOpenAppSettings,
          child: const Text('Open App Settings'),
        ),
      ]);
    } else {
      title = 'Couldn’t get location';
    }

    actions.addAll([
      const SizedBox(height: 8),
      OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
    ]);

    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.location_off, size: 48),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 12),
        ...actions,
      ]),
    );
  }
}
