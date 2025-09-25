// lib/src/services/review_api_service.dart
// Updated to use place-scoped fetch and atomic insert via RPC.
// NOTE: ReviewDto is defined in reviews_page.dart and imported here.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/reviews_page.dart' show ReviewDto;

enum ReviewSort { newest, oldest, helpful }

class ReviewApiService {
  ReviewApiService(this._sb);
  final SupabaseClient _sb;

  static const String _table = 'reviews';

  /// Back-compat: your older fetch() that listed everything.
  /// You can keep it if elsewhere used; otherwise switch to fetchByPlace().
  Future<List<ReviewDto>> fetch({
    int? stars,
    String? search,
    ReviewSort sort = ReviewSort.newest,
    int limit = 30,
    int offset = 0,
    bool includeOwnEvenIfReported = true,
  }) async {
    final uid = _sb.auth.currentUser?.id;

    // Base: non-reported or own
    var q = _sb
        .from(_table)
        .select()
        .or('reported.eq.false${uid != null ? ',user_id.eq.$uid' : ''}');

    if (stars != null && stars >= 1 && stars <= 5) {
      q = q.eq('rating', stars);
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      q = q.or('comment.ilike.%$s%,display_name.ilike.%$s%');
    }

    switch (sort) {
      case ReviewSort.newest:
        q = q.order('created_at', ascending: false);
        break;
      case ReviewSort.oldest:
        q = q.order('created_at', ascending: true);
        break;
      case ReviewSort.helpful:
        q = q
            .order('helpful_count', ascending: false)
            .order('created_at', ascending: false);
        break;
    }

    q = q.range(offset, offset + limit - 1);

    final data = await q;
    return (data as List)
        .map((e) => ReviewDto.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// New: fetch reviews scoped to a specific place.
  Future<List<ReviewDto>> fetchByPlace({
    required String placeId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool desc = true,
  }) async {
    final res = await _sb
        .from(_table)
        .select()
        .eq('place_id', placeId)
        .order(orderBy, ascending: !desc)
        .range(offset, offset + limit - 1);

    return (res as List)
        .map((e) => ReviewDto.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// New: create review via RPC that also updates area_scores atomically.
  /// SQL: add_review_and_update_score(
  ///   p_place_id uuid, p_user_id uuid, p_display_name text,
  ///   p_rating int, p_comment text, p_anonymous boolean)
  Future<ReviewDto> createForPlaceViaRpc({
    required String placeId,
    required String userId,
    required String displayName,
    required int rating,
    required String comment,
    required bool anonymous,
  }) async {
    final res = await _sb.rpc('add_review_and_update_score', params: {
      'p_place_id': placeId,
      'p_user_id': userId,
      'p_display_name': displayName,
      'p_rating': rating,
      'p_comment': comment,
      'p_anonymous': anonymous,
    });

    return ReviewDto.fromMap(res as Map<String, dynamic>);
  }

  /// Keep your delete as-is (RLS should guard ownership).
  Future<void> delete(String reviewId) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _sb.from(_table).delete().eq('id', reviewId);
  }

  /// Keep your report flow.
  Future<void> report(String reviewId, {String? reason}) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await _sb.from(_table).update({'reported': true}).eq('id', reviewId);

    // Or insert into review_reports table if you use that approach.
  }

  /// Keep your helpful RPC name for compatibility.
  Future<void> markHelpful(String reviewId) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _sb.rpc('mark_review_helpful', params: {'p_review_id': reviewId});
  }

  /// Realtime subscription (unchanged).
  RealtimeChannel subscribe(void Function() onChange) {
    final ch = _sb.channel('reviews-ch')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: _table,
        callback: (_) => onChange(),
      )
      ..subscribe();
    return ch;
  }

  Future<void> unsubscribe(RealtimeChannel ch) async {
    await _sb.removeChannel(ch);
  }
}
