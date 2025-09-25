import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewDto {
  final String id;
  final String userId;
  final String displayName;
  final int rating;
  final String comment;
  final bool anonymous;
  final bool reported;
  final int helpfulCount;
  final DateTime createdAt;

  ReviewDto({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.rating,
    required this.comment,
    required this.anonymous,
    required this.reported,
    required this.helpfulCount,
    required this.createdAt,
  });

  factory ReviewDto.fromMap(Map<String, dynamic> m) => ReviewDto(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    displayName: m['display_name'] as String,
    rating: (m['rating'] as num).toInt(),
    comment: m['comment'] as String,
    anonymous: (m['anonymous'] as bool?) ?? false,
    reported: (m['reported'] as bool?) ?? false,
    helpfulCount: (m['helpful_count'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

enum ReviewSort { newest, oldest, helpful }

class ReviewApiService {
  final _sb = Supabase.instance.client;

  Future<List<ReviewDto>> fetch({
    int? stars,                   // exact match filter, 1..5
    String? search,               // search in comment / display_name
    ReviewSort sort = ReviewSort.newest,
    int limit = 30,
    int offset = 0,
    bool includeOwnEvenIfReported = true,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    var query = _sb.from('reviews').select();

    // reported=false policy already allows reading;
    // to include own reported, union with own rows
    if (includeOwnEvenIfReported && uid != null) {
      // Workaround: query all non-reported + own
      query = _sb.rpc('',
        params: {}
      ); // placeholder to keep IDE happy (we’ll just chain filters below)
    }

    // Base: non-reported or (own)
    final base = _sb
        .from('reviews')
        .select()
        .or('reported.eq.false${uid != null ? ',user_id.eq.$uid' : ''}');

    var q = base;

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
        q = q.order('helpful_count', ascending: false)
             .order('created_at', ascending: false);
        break;
    }

    q = q.range(offset, offset + limit - 1);

    final data = await q;
    return (data as List).map((e) => ReviewDto.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<ReviewDto> create({
    required int rating,
    required String comment,
    required bool anonymous,
    required String displayName, // from profile
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw Exception('Not authenticated');
    }
    final inserted = await _sb.from('reviews').insert({
      'user_id': user.id,
      'display_name': displayName,
      'rating': rating,
      'comment': comment,
      'anonymous': anonymous,
    }).select().single();
    return ReviewDto.fromMap(inserted);
  }

  Future<void> delete(String reviewId) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    // RLS ensures only owner can delete
    await _sb.from('reviews').delete().eq('id', reviewId);
  }

  Future<void> report(String reviewId, {String? reason}) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // choose one:
    // A) simple: set reported=true (only admins later un-report)
    await _sb.from('reviews').update({'reported': true})
      .eq('id', reviewId);

    // B) or: create report row (keeps review visible until threshold)
    // await _sb.from('review_reports').insert({
    //   'review_id': reviewId,
    //   'user_id': user.id,
    //   'reason': reason,
    // });
  }

  Future<void> markHelpful(String reviewId) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _sb.rpc('mark_review_helpful', params: {'p_review_id': reviewId});
  }

  /// (Optional) realtime subscription
  RealtimeChannel subscribe(void Function() onChange) {
    final ch = _sb.channel('reviews-ch')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reviews',
        callback: (_) => onChange(),
      )
      ..subscribe();
    return ch;
  }

  Future<void> unsubscribe(RealtimeChannel ch) async {
    await _sb.removeChannel(ch);
  }
}
