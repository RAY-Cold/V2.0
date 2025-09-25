import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isSignIn = true;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() { _email.dispose(); _password.dispose(); _name.dispose(); super.dispose(); }

  Future<void> _handleAuth() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (isSignIn) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _email.text.trim(), password: _password.text,
        );
        await _ensureProfileExists();
      } else {
        await Supabase.instance.client.auth.signUp(
          email: _email.text.trim(), password: _password.text,
          data: {'full_name': _name.text.trim()},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Account created. Verify email if required, then Sign In.'),
          ));
        }
      }
    } on AuthException catch (e) { setState(() => _error = e.message); }
    catch (e) { setState(() => _error = 'Unexpected error: $e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _ensureProfileExists() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final existing = await Supabase.instance.client
      .from('profiles').select('id').eq('id', user.id).maybeSingle();
    if (existing == null) {
      await Supabase.instance.client.from('profiles').insert({
        'id': user.id,
        'email': user.email,
        'full_name': _name.text.trim().isNotEmpty
            ? _name.text.trim() : (user.userMetadata?['full_name'] ?? ''),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: kBgGradient),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('TourSecure')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  constraints: const BoxConstraints(maxWidth: 500),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _pill('Sign In', isSignIn, () => setState(() => isSignIn = true)),
                            _pill('Sign Up', !isSignIn, () => setState(() => isSignIn = false)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (!isSignIn) ...[
                        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')),
                        const SizedBox(height: 12),
                      ],
                      TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                      const SizedBox(height: 12),
                      TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _handleAuth,
                          child: _loading
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(isSignIn ? 'Sign In' : 'Create Account'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Expanded _pill(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withOpacity(0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.white.withOpacity(0.85))),
        ),
      ),
    );
  }
}
