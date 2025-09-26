// lib/src/services/itinerary_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/itinerary/data/itinerary_dto.dart';

class ItineraryService {
  ItineraryService(this._sb);
  final SupabaseClient _sb;

  static const String _table = 'itineraries';

  /// Back-compat wrapper used by older pages.
  Future<List<ItineraryDto>> listMine({
    int limit = 200,
    bool ascending = true,
    bool onlyUpcoming = false,
    String? search,
    DateTime? from,
    DateTime? to,
    int offset = 0,
  }) {
    return list(
      limit: limit,
      ascending: ascending,
      onlyUpcoming: onlyUpcoming,
      search: search,
      from: from,
      to: to,
      offset: offset,
    );
  }

  /// List the current user's itinerary items.
  Future<List<ItineraryDto>> list({
    String? search,            // search in title/location/details
    DateTime? from,            // filter start_date >= from (UTC)
    DateTime? to,              // filter start_date <= to   (UTC)
    bool onlyUpcoming = false, // filter start_date >= today (UTC midnight)
    bool ascending = true,     // order by start_date
    int limit = 200,
    int offset = 0,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return [];

    final nowUtc = DateTime.now().toUtc();
    final todayUtcMidnight = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);

    // Build filters first on a FilterBuilder...
    var q = _sb.from(_table).select().eq('user_id', uid);

    if (onlyUpcoming) {
      q = q.gte('start_date', todayUtcMidnight.toIso8601String());
    }
    if (from != null) {
      q = q.gte('start_date', from.toUtc().toIso8601String());
    }
    if (to != null) {
      q = q.lte('start_date', to.toUtc().toIso8601String());
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      q = q.or('title.ilike.%$s%,location.ilike.%$s%,details.ilike.%$s%');
    }

    // ...then apply ordering/pagination inline (returns TransformBuilder) without
    // reassigning to the FilterBuilder variable (avoids type-mismatch error).
    final res = await q
        .order('start_date', ascending: ascending)
        .range(offset, offset + limit - 1);

    return (res as List)
        .map((e) => ItineraryDto.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a new itinerary item for the current user.
  ///
  /// NOTE: we intentionally DO NOT send `reference_no` here to avoid UNIQUE
  /// collisions when the DB has a unique index for it. Let the DB default
  /// generate it or leave it NULL (Postgres allows multiple NULLs).
  Future<ItineraryDto> create({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    String? location,
    String? details,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final payload = <String, dynamic>{
      'user_id': uid,
      'title': title.trim(),
      'start_date': startDate.toUtc().toIso8601String(),
      'end_date': endDate.toUtc().toIso8601String(),
      if (location != null && location.trim().isNotEmpty) 'location': location.trim(),
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
      // no 'reference_no'
    };

    final inserted =
        await _sb.from(_table).insert(payload).select().single();
    return ItineraryDto.fromMap(inserted as Map<String, dynamic>);
  }

  /// Mark item as done / not done.
  Future<ItineraryDto> setDone(String id, bool isDone) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final updated = await _sb
        .from(_table)
        .update({'is_done': isDone})
        .match({'id': id, 'user_id': uid})
        .select()
        .single();

    return ItineraryDto.fromMap(updated as Map<String, dynamic>);
  }

  /// Update fields (does not touch reference_no).
  Future<ItineraryDto> update({
    required String id,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? location,
    String? details,
    bool? isDone,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final patch = <String, dynamic>{};
    if (title != null) patch['title'] = title.trim();
    if (startDate != null) patch['start_date'] = startDate.toUtc().toIso8601String();
    if (endDate != null) patch['end_date'] = endDate.toUtc().toIso8601String();
    if (location != null) patch['location'] = location.trim();
    if (details != null) patch['details'] = details.trim();
    if (isDone != null) patch['is_done'] = isDone;

    final updated = await _sb
        .from(_table)
        .update(patch)
        .match({'id': id, 'user_id': uid})
        .select()
        .single();

    return ItineraryDto.fromMap(updated as Map<String, dynamic>);
  }

  /// Delete one of my itinerary items.
  Future<void> delete(String id) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    await _sb.from(_table).delete().match({'id': id, 'user_id': uid});
  }
}
