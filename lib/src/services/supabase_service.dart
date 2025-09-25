import 'package:supabase_flutter/supabase_flutter.dart';


class SupaService {
static final client = Supabase.instance.client;


/// Ensures a profile row exists for the current user. Safe to call after sign up.
static Future<void> ensureProfileRow({String? displayName}) async {
final user = client.auth.currentUser;
if (user == null) return;


final existing = await client
.from('profiles')
.select('id')
.eq('id', user.id)
.maybeSingle();


if (existing == null) {
await client.from('profiles').insert({
'id': user.id,
'email': user.email,
'display_name': displayName ?? user.email?.split('@').first,
});
}
}


static Future<int?> fetchUserSafetyScore() async {
final user = client.auth.currentUser;
if (user == null) return null;
final data = await client
.from('profiles')
.select('user_safety_score')
.eq('id', user.id)
.maybeSingle();
return (data?['user_safety_score'] as int?) ?? 80;
}
}