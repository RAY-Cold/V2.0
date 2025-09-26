/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/heatmap_page.dart';
import '../pages/reviews_page.dart';
import '../pages/efir_page.dart';
import '../pages/itinerary_page.dart';
import '../pages/digital_id_page.dart';
import '../pages/about_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      // Use LEFT drawer (not endDrawer) so the hamburger appears top-left automatically.
      drawer: _MainDrawer(),
      appBar: AppBar(
        title: const Text('TourSecure'),
        // No actions/leading needed—AppBar shows a working hamburger when `drawer:` is set.
      ),
      // Make the whole page scrollable on small screens.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;

          final sosButton = Center(
            child: ScaleTransition(
              scale: _scale,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  minimumSize: const Size(220, 220),
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SOS triggered (stub)!')),
                  );
                },
                child: const Text(
                  'S.O.S',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
              ),
            ),
          );

          final areaCard = const _AreaSafetyCard();

          final userScoreCard = Card(
            child: ListTile(
              leading: const Icon(Icons.shield),
              title: const Text('Your Safety Score'),
              subtitle: Text(user?.email ?? ''),
              trailing: const _ScoreBadge(score: 50), // placeholder
            ),
          );

          // WIDE layout: SOS + right sidebar, with vertical scroll if needed.
          if (isWide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: SOS + bottom user card
                    Expanded(
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          sosButton,
                          const SizedBox(height: 24),
                          userScoreCard,
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right: area safety sidebar
                    SizedBox(
                      width: 300,
                      child: Column(
                        children: [
                          areaCard,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // MOBILE layout: stacked and scrollable.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                areaCard,
                const SizedBox(height: 24),
                sosButton,
                const SizedBox(height: 24),
                userScoreCard,
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AreaSafetyCard extends StatelessWidget {
  const _AreaSafetyCard();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Area Safety Score', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Current area: (stubbed)'),
            SizedBox(height: 12),
            _ScoreBadge(score: 72), // placeholder
          ],
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score; // 0-100
  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (score >= 75) {
      color = Colors.green;
    } else if (score >= 50) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '$score / 100',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _MainDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              child: Text(
                'Menu',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            _navTile(context, Icons.map, 'Heatmap', const HeatmapPage()),
            _navTile(context, Icons.rate_review, 'Reviews', const ReviewsPage()),
            _navTile(context, Icons.report, 'eFIR', const EFIRPage()),
            _navTile(context, Icons.list_alt, 'Itinerary', const ItineraryPage()),
            _navTile(context, Icons.badge, 'Digital ID', const DigitalIDPage()),
            _navTile(context, Icons.info, 'About Us', const AboutPage()),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) Navigator.of(context).pop();
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
      onTap: () {
        Navigator.of(context).pop(); // close drawer
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      },
    );
  }
}
*/import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../pages/pages.dart'; // barrel: heatmap_page.dart, reviews_page.dart, efir_page.dart, etc.

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.96, end: 1.06).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

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
          // ensure the menu button always works (useful on web/transparent bars)
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 760;
            final sos = _SosButton(scale: _scale);
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
  const _SosButton({required this.scale});

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
            onPressed: () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('SOS triggered (stub)!')));
            },
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
                  _navTile(context, Icons.assignment, 'e-FIR', const EFIRPage()), // ✅ e-FIR
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
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) Navigator.of(context).pop();
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
        // Use pushReplacement so we don't stack multiple pages when navigating via the drawer
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
      },
    );
  }
}
