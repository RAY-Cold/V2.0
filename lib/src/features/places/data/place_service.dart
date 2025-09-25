import 'package:supabase_flutter/supabase_flutter.dart';
import 'place_dto.dart';

class PlaceService {
  PlaceService(this.client);
  final SupabaseClient client;

  Future<List<PlaceDto>> search(String q) async {
    if (q.trim().isEmpty) return [];
    final res = await client
      .from('places')
      .select('id,name,address')
      .ilike('name', '%${q.trim()}%')
      .limit(10);
    return (res as List).map((e) => PlaceDto.fromMap(e as Map<String,dynamic>)).toList();
  }

  Future<Map<String,dynamic>?> fetchScore(String placeId) async {
    final r = await client.from('area_scores').select().eq('place_id', placeId).maybeSingle();
    return (r as Map<String,dynamic>?);
  }
}
