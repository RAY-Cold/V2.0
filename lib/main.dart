/*import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Adjust paths if yours differ
import 'src/home/home_page.dart';
import 'src/pages/heatmap_page.dart';
import 'src/pages/reviews_page.dart';
import 'src/pages/efir_page.dart';
import 'src/pages/itinerary_page.dart';
import 'src/pages/digital_id_page.dart';
import 'src/pages/about_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final url = dotenv.env['SUPABASE_URL'];
  final anon = dotenv.env['SUPABASE_ANON_KEY'];

  if (url == null || anon == null) {
    throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
  }

  await Supabase.initialize(
    url: url,
    anonKey: anon,
    debug: true,
  );

  runApp(const TourSecureApp());
}

class TourSecureApp extends StatelessWidget {
  const TourSecureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TourSecure',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      // Use string routes (pages don’t expose a static .route)
      routes: {
        '/home': (_) => const HomePage(),
        '/heatmap': (_) => const HeatmapPage(),
        '/reviews': (_) => const ReviewsPage(),
        '/efir': (_) => const EFIRPage(),
        '/itinerary': (_) => const ItineraryPage(),
        '/digital-id': (_) => const DigitalIDPage(),
        '/about': (_) => const AboutPage(),
      },
    );
  }
}

/// Shows sign-in/up OR app content based on Supabase auth state.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStateStream;

  @override
  void initState() {
    super.initState();
    _authStateStream = Supabase.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return StreamBuilder<AuthState>(
      stream: _authStateStream,
      initialData: AuthState(AuthChangeEvent.initialSession, session),
      builder: (context, snapshot) {
        final hasSession = snapshot.data?.session != null;
        return hasSession ? const HomePage() : const SignInSignUpPage();
      },
    );
  }
}

/// Simple combined Sign-In / Sign-Up screen.
class SignInSignUpPage extends StatefulWidget {
  const SignInSignUpPage({super.key});

  @override
  State<SignInSignUpPage> createState() => _SignInSignUpPageState();
}

class _SignInSignUpPageState extends State<SignInSignUpPage>
    with SingleTickerProviderStateMixin {
  bool isSignIn = true;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (isSignIn) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await _ensureProfileExists();
      } else {
        final res = await Supabase.instance.client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'full_name': _name.text.trim()},
        );
        if (res.user != null) {
          await _createInitialProfile(res.user!);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Account created. Check email if confirmations are enabled.')));
        }
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureProfileExists() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final existing = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existing == null) {
      await _createInitialProfile(user);
    }
  }

  Future<void> _createInitialProfile(User user) async {
    await Supabase.instance.client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'full_name':
          _name.text.trim().isNotEmpty ? _name.text.trim() : (user.userMetadata?['full_name'] ?? ''),
      'created_at': DateTime.now().toIso8601String(),
      'safety_score': 50,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('TourSecure',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Sign In')),
                    ButtonSegment(value: false, label: Text('Sign Up')),
                  ],
                  selected: {isSignIn},
                  onSelectionChanged: (s) => setState(() => isSignIn = s.first),
                ),
                const SizedBox(height: 18),
                if (!isSignIn) ...[
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', border: OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _handleAuth,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isSignIn ? 'Sign In' : 'Create Account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
*/
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/theme/app_theme.dart';
import 'src/auth/auth_screen.dart';
import 'src/home/home_page.dart';
import 'src/pages/heatmap_page.dart';
import 'src/pages/reviews_page.dart';
import 'src/pages/efir_page.dart';
import 'src/pages/itinerary_page.dart';
import 'src/pages/digital_id_page.dart';
import 'src/pages/about_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final url = dotenv.env['SUPABASE_URL'];
  final anon = dotenv.env['SUPABASE_ANON_KEY'];
  if (url == null || anon == null) {
    throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
  }

  await Supabase.initialize(url: url, anonKey: anon, debug: true);
  runApp(const TourSecureApp());
}

class TourSecureApp extends StatelessWidget {
  const TourSecureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TourSecure',
      theme: AppTheme.light(),
      home: const _AuthGate(),
      routes: {
        '/home': (_) => const HomePage(),
        '/heatmap': (_) => const HeatmapPage(),
        '/reviews': (_) => const ReviewsPage(),
        '/efir': (_) => const EFIRPage(),
        '/itinerary': (_) => const ItineraryPage(),
        '/digital-id': (_) => const DigitalIDPage(),
        '/about': (_) => const AboutPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, auth.currentSession),
      builder: (context, snapshot) {
        final hasSession = snapshot.data?.session != null;
        return hasSession ? const HomePage() : const AuthScreen();
      },
    );
  }
}
