// lib/src/home/home_page.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../pages/pages.dart'; // barrel: heatmap_page.dart, reviews_page.dart, efir_page.dart, etc.
import '../services/efir_service.dart'; // <-- for auto eFIR submit

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  // SOS / EFIR
  late final EfirService _efirService;
  Timer? _sosTimer;
  bool _sosRunning = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.96, end: 1.06).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _efirService = EfirService(Supabase.instance.client);
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  // ---------------- SOS flow ----------------

  Future<void> _onSosPressed() async {
    if (_sosRunning) return;
    _sosRunning = true;

    final cancelled = await _showSosCountdownDialog(); // true if user tapped Cancel
    _sosRunning = false;

    if (!mounted) return;
    if (cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOS cancelled')));
      return;
    }
    await _submitAutoEfir();
  }

  Future<bool> _showSosCountdownDialog() async {
    // returns true if cancelled, false if countdown ended
    final sec = ValueNotifier<int>(5);
    final done = Completer<bool>();

    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (sec.value > 1) {
        sec.value--;
      } else {
        t.cancel();
        if (!done.isCompleted) done.complete(false);
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Sending SOS…'),
          content: ValueListenableBuilder<int>(
            valueListenable: sec,
            builder: (_, s, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Auto submit in', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text('$s', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Tap Cancel if this was accidental.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _sosTimer?.cancel();
                if (!done.isCompleted) done.complete(true); // cancelled
                Navigator.of(ctx).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    return done.future;
  }

  Future<void> _submitAutoEfir() async {
    // Try to include location (optional)
    double? lat, lng;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        if (p != LocationPermission.denied && p != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition();
          lat = pos.latitude;
          lng = pos.longitude;
        }
      }
    } catch (_) {}

    try {
      final now = DateTime.now().toLocal();

      // Capture the created report so we can show a concrete reference/id
      final created = await _efirService.create(
        name: 'SOS Alert', // maps to title
        contact: null,
        description: 'Automatic SOS triggered from Home button at $now.',
        lat: lat,
        lng: lng,
        files: const <EfirUploadable>[],
      );

      if (!mounted) return;

      final ref = (created.referenceNo.isNotEmpty)
          ? created.referenceNo
          : (created.id?.toString() ?? '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.isEmpty ? 'SOS submitted (Pending)' : 'SOS submitted: $ref')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit SOS: $e')));
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: kBgGradient),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: const _MainDrawer(), // left hamburger
        appBar: AppBar(
  title: const Text('TourSecure'),
  backgroundColor: Colors.transparent,
  // make all app bar icons & text white
  foregroundColor: Colors.white,
  iconTheme: const IconThemeData(color: Colors.white),
  // keep your working hamburger even on transparent bars
  leading: Builder(
    builder: (ctx) => IconButton(
      icon: const Icon(Icons.menu, color: Colors.white),
      onPressed: () => Scaffold.of(ctx).openDrawer(),
      tooltip: MaterialLocalizations.of(ctx).openAppDrawerTooltip,
    ),
  ),
),

        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 760;
            final sos = _SosButton(scale: _scale, onPressed: _onSosPressed);
            final areaCard = const _GlassCard(child: _AreaSafety());
            final userCard = _GlassCard(
              child: ListTile(
                leading: const Icon(Icons.shield, color: Colors.white),
                title: const Text('Your Safety Score',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(user?.email ?? '', style: const TextStyle(color: Colors.white70)),
                trailing: const _ScoreBadge(score: 50),
              ),
            );

            if (isWide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            sos,
                            const SizedBox(height: 24),
                            userCard,
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      const SizedBox(width: 320, child: _GlassCard(child: _AreaSafety())),
                    ],
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  areaCard,
                  const SizedBox(height: 24),
                  sos,
                  const SizedBox(height: 24),
                  userCard,
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  final Animation<double> scale;
  final VoidCallback onPressed;
  const _SosButton({required this.scale, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: scale,
          builder: (_, __) {
            final v = (scale.value - 0.96) / (1.06 - 0.96);
            return Container(
              width: 260 + v * 30,
              height: 260 + v * 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withOpacity(0.35),
                    blurRadius: 60 + v * 30,
                    spreadRadius: 6 + v * 6,
                  ),
                ],
              ),
            );
          },
        ),
        ScaleTransition(
          scale: scale,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              minimumSize: const Size(220, 220),
              padding: EdgeInsets.zero,
              backgroundColor: const Color(0xFFFF4D67),
              foregroundColor: Colors.white,
            ),
            onPressed: onPressed,
            child: const Text('S.O.S',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 2)),
          ),
        ),
      ],
    );
  }
}

class _AreaSafety extends StatelessWidget {
  const _AreaSafety();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: const [
        Text('Area Safety Score', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        SizedBox(height: 10),
        Text('Current area: (stubbed)', style: TextStyle(color: Colors.white70)),
        SizedBox(height: 14),
        _ScoreBadge(score: 72),
      ],
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  const _ScoreBadge({required this.score});
  @override
  Widget build(BuildContext context) {
    Color color;
    if (score >= 75) {
      color = Colors.greenAccent;
    } else if (score >= 50) {
      color = Colors.orangeAccent;
    } else {
      color = Colors.redAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text('$score / 100', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _MainDrawer extends StatelessWidget {
  const _MainDrawer();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final initials = (user?.email ?? 'U?').substring(0, 2).toUpperCase();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(user?.email ?? ''),
              accountEmail: const Text(''),
              currentAccountPicture: CircleAvatar(
                backgroundColor: const Color(0xFFFF4D67),
                child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _navTile(context, Icons.map, 'Heatmap', const HeatmapPage()),
                  _navTile(context, Icons.rate_review, 'Reviews', const ReviewsPage()),
                  _navTile(context, Icons.assignment, 'e-FIR', const EFIRPage()),
                  _navTile(context, Icons.list_alt, 'Itinerary', const ItineraryPage()),
                  _navTile(context, Icons.badge, 'Digital ID', const DigitalIDPage()),
                  _navTile(context, Icons.info, 'About Us', const AboutPage()),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () async {
                try {
                  await Supabase.instance.client.auth.signOut();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign out failed: $e')),
                    );
                  }
                  return;
                }
                if (!context.mounted) return;

                // Close the drawer (if open)
                Navigator.of(context).pop();

                // Navigate to the root route and clear history so the auth gate / login shows
                // Make sure your MaterialApp routes map '/' to your splash/auth gate.
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
            ),
          ],
        ),
      ),
    );
  }

  ListTile _navTile(BuildContext context, IconData icon, String label, Widget page) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).pop(); // close drawer
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
      },
    );
  }
}
