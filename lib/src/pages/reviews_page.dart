import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:postgrest/postgrest.dart'; // ✅ Needed for PostgrestBuilder/Filter/Transform

/// =======================================================
/// Supabase DTO + Service
/// =======================================================

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
  final SupabaseClient _sb = Supabase.instance.client;

  Future<List<ReviewDto>> fetch({
    int? stars, // 1..5
    String? search,
    ReviewSort sort = ReviewSort.newest,
    int limit = 50,
    int offset = 0,
  }) async {
    final uid = _sb.auth.currentUser?.id;

    // Start as PostgrestBuilder so reassignment after .order()/.range() is type-safe.
    PostgrestBuilder query = _sb
        .from('reviews')
        .select()
        .or('reported.eq.false${uid != null ? ',user_id.eq.$uid' : ''}');

    if (stars != null && stars >= 1 && stars <= 5) {
      // eq/or live on the Filter builder
      query = (query as PostgrestFilterBuilder).eq('rating', stars);
    }

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = (query as PostgrestFilterBuilder)
          .or('comment.ilike.%$s%,display_name.ilike.%$s%');
    }

    // order/range live on the Transform builder
    switch (sort) {
      case ReviewSort.newest:
        query = (query as PostgrestTransformBuilder)
            .order('created_at', ascending: false);
        break;
      case ReviewSort.oldest:
        query = (query as PostgrestTransformBuilder)
            .order('created_at', ascending: true);
        break;
      case ReviewSort.helpful:
        query = (query as PostgrestTransformBuilder)
            .order('helpful_count', ascending: false)
            .order('created_at', ascending: false);
        break;
    }

    query =
        (query as PostgrestTransformBuilder).range(offset, offset + limit - 1);

    final data = await query;
    return (data as List)
        .map((e) => ReviewDto.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<ReviewDto> create({
    required int rating,
    required String comment,
    required bool anonymous,
    String? displayNameOverride,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw Exception('Not authenticated');
    }

    // Try to use user metadata for display name if available
    final meta = user.userMetadata ?? {};
    final dn = displayNameOverride ??
        (meta['full_name'] ??
            meta['name'] ??
            meta['display_name'] ??
            'TourSecure User');

    final inserted = await _sb.from('reviews').insert({
      'user_id': user.id,
      'display_name': dn,
      'rating': rating,
      'comment': comment,
      'anonymous': anonymous,
    }).select().single();

    return ReviewDto.fromMap(inserted as Map<String, dynamic>);
  }

  Future<void> delete(String reviewId) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _sb.from('reviews').delete().eq('id', reviewId);
  }

  Future<void> report(String reviewId, {String? reason}) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Simple path: set reported = true (owner-only update via policy)
    // If you want anyone to report (not just owner), use review_reports table instead
    await _sb.from('reviews').update({'reported': true}).eq('id', reviewId);

    // Alternate (commented):
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

  RealtimeChannel subscribe(void Function() onChange) {
    final ch = _sb.channel('reviews-realtime')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reviews',
        callback: (_) => onChange(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'review_helpful',
        callback: (_) => onChange(),
      )
      ..subscribe();
    return ch;
  }

  Future<void> unsubscribe(RealtimeChannel ch) async {
    await _sb.removeChannel(ch);
  }
}

/// =======================================================
/// UI Models + Helpers (kept close to your original)
/// =======================================================

class Review {
  final String id;
  final String userId;
  final String displayName;
  final int rating; // 1..5
  final String comment;
  final DateTime createdAt;
  final bool anonymous;
  final int helpfulCount;
  final bool reported;

  Review({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.anonymous = false,
    this.helpfulCount = 0,
    this.reported = false,
  });

  Review copyWith({
    String? id,
    String? userId,
    String? displayName,
    int? rating,
    String? comment,
    DateTime? createdAt,
    bool? anonymous,
    int? helpfulCount,
    bool? reported,
  }) {
    return Review(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
      anonymous: anonymous ?? this.anonymous,
      helpfulCount: helpfulCount ?? this.helpfulCount,
      reported: reported ?? this.reported,
    );
  }
}

enum SortBy { newest, oldest, helpful }

String _fmtDate(DateTime dt) {
  return '${_two(dt.day)} ${_mon(dt.month)} ${dt.year}, ${_two(dt.hour)}:${_two(dt.minute)}';
}

String _mon(int m) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return names[m - 1];
}

String _two(int n) => n.toString().padLeft(2, '0');

class StarRow extends StatelessWidget {
  final int filled; // 0..5
  final double size;
  final void Function(int star)? onTap; // star = 1..5
  final bool interactive;
  const StarRow({
    super.key,
    required this.filled,
    this.size = 20,
    this.onTap,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final idx = i + 1;
        final icon = idx <= filled ? Icons.star : Icons.star_border;
        final color = idx <= filled ? Colors.amber : Colors.grey.shade400;
        final w = Icon(icon, size: size, color: color);
        if (!interactive) return w;
        return InkWell(
          onTap: () => onTap?.call(idx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: w,
          ),
        );
      }),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const Pill(
      {super.key,
      required this.text,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(.12)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// =======================================================
/// Reviews Page (Supabase-backed)
/// =======================================================

class ReviewsPage extends StatefulWidget {
  const ReviewsPage({super.key});

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  final api = ReviewApiService();
  RealtimeChannel? _ch;

  List<Review> _all = [];
  bool _loading = true;

  // form
  int _rating = 0;
  String _comment = '';
  bool _anonymous = false;
  bool _submitting = false;

  // list controls
  String _query = '';
  int _filterStars = 0; // 0 = all, else exact stars
  SortBy _sortBy = SortBy.newest;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = api.subscribe(() {
      _load(); // auto refresh on DB changes
    });
  }

  @override
  void dispose() {
    if (_ch != null) {
      api.unsubscribe(_ch!);
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final dtos = await api.fetch(
      stars: _filterStars == 0 ? null : _filterStars,
      search: _query.isEmpty ? null : _query,
      sort: switch (_sortBy) {
        SortBy.newest => ReviewSort.newest,
        SortBy.oldest => ReviewSort.oldest,
        SortBy.helpful => ReviewSort.helpful,
      },
    );

    _all = dtos
        .map((d) => Review(
              id: d.id,
              userId: d.userId,
              displayName: d.displayName,
              rating: d.rating,
              comment: d.comment,
              createdAt: d.createdAt,
              anonymous: d.anonymous,
              helpfulCount: d.helpfulCount,
              reported: d.reported,
            ))
        .toList();

    setState(() => _loading = false);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    if (_rating == 0 || _comment.trim().isEmpty) {
      _snack('Please add a star rating and a comment.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await api.create(
        rating: _rating,
        comment: _comment.trim(),
        anonymous: _anonymous,
      );
      setState(() {
        _rating = 0;
        _comment = '';
        _anonymous = false;
      });
      await _load();
    } catch (e) {
      _snack(e.toString());
    } finally {
      setState(() => _submitting = false);
    }
  }

  void _toggleHelpful(Review r) async {
    try {
      await api.markHelpful(r.id);
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _report(Review r) async {
    try {
      await api.report(r.id);
      _snack('Reported.');
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _delete(Review r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await api.delete(r.id);
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  double get _avg {
    if (_all.isEmpty) return 0;
    final sum = _all.fold<int>(0, (a, b) => a + b.rating);
    return sum / _all.length;
  }

  Map<int, int> get _distribution {
    final map = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in _all) {
      map[r.rating] = (map[r.rating] ?? 0) + 1;
    }
    return map;
  }

  List<Review> get _visible {
    // Server did filtering/sorting already, but keep local fallback for search/stars
    var list = _all.where((r) => !r.reported || true).toList(); // own reported included by fetch

    if (_filterStars != 0) {
      list = list.where((r) => r.rating == _filterStars).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((r) =>
              r.comment.toLowerCase().contains(q) ||
              (!r.anonymous && r.displayName.toLowerCase().contains(q)))
          .toList();
    }

    list.sort((a, b) {
      switch (_sortBy) {
        case SortBy.newest:
          return b.createdAt.compareTo(a.createdAt);
        case SortBy.oldest:
          return a.createdAt.compareTo(b.createdAt);
        case SortBy.helpful:
          final c = b.helpfulCount.compareTo(a.helpfulCount);
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final dist = _distribution;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reviews'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _SummaryCard(
                        avg: _avg, total: _all.length, distribution: dist),
                    const SizedBox(height: 16),
                    _Controls(
                      query: _query,
                      onQuery: (v) => setState(() => _query = v),
                      filterStars: _filterStars,
                      onFilterStars: (s) async {
                        setState(() => _filterStars = s);
                        await _load();
                      },
                      sortBy: _sortBy,
                      onSortBy: (s) async {
                        setState(() => _sortBy = s);
                        await _load();
                      },
                    ),
                    const SizedBox(height: 16),
                    _AddReviewCard(
                      rating: _rating,
                      onStar: (s) => setState(() => _rating = s),
                      comment: _comment,
                      onComment: (t) => setState(() => _comment = t),
                      anonymous: _anonymous,
                      onAnon: (v) => setState(() => _anonymous = v),
                      submitting: _submitting,
                      onSubmit: _submit,
                    ),
                    const SizedBox(height: 16),
                    if (_visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'No reviews yet.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    else
                      ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemBuilder: (_, i) {
                          final r = _visible[i];
                          final isMine =
                              r.userId == Supabase.instance.client.auth.currentUser?.id;
                          return _ReviewTile(
                            review: r,
                            isMine: isMine,
                            onHelpful: () => _toggleHelpful(r),
                            onReport: () => _report(r),
                            onDelete: isMine ? () => _delete(r) : null,
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: _visible.length,
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

/// =======================================================
/// Summary card
/// =======================================================

class _SummaryCard extends StatelessWidget {
  final double avg;
  final int total;
  final Map<int, int> distribution;
  const _SummaryCard(
      {required this.avg, required this.total, required this.distribution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bars = [5, 4, 3, 2, 1];
    final maxCount = (distribution.values.isEmpty)
        ? 1
        : (distribution.values.reduce((a, b) => a > b ? a : b)).clamp(1, 9999);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // average
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Text(avg.toStringAsFixed(1),
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  StarRow(filled: avg.round(), size: 22),
                  const SizedBox(height: 6),
                  Text('$total review${total == 1 ? '' : 's'}',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // distribution
            Expanded(
              flex: 7,
              child: Column(
                children: [
                  for (final s in bars)
                    _BarRow(
                      label: '$s★',
                      value: (distribution[s] ?? 0).toDouble(),
                      max: maxCount.toDouble(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  const _BarRow(
      {required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final pct = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 34, child: Text(label, textAlign: TextAlign.right)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 34, child: Text(value.toInt().toString(), textAlign: TextAlign.left)),
        ],
      ),
    );
  }
}

/// =======================================================
/// Controls (search, chips, sort)
/// =======================================================

class _Controls extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQuery;
  final int filterStars; // 0 or 1..5
  final ValueChanged<int> onFilterStars;
  final SortBy sortBy;
  final ValueChanged<SortBy> onSortBy;

  const _Controls({
    required this.query,
    required this.onQuery,
    required this.filterStars,
    required this.onFilterStars,
    required this.sortBy,
    required this.onSortBy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // search
        TextField(
          decoration: InputDecoration(
            hintText: 'Search reviews...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          onChanged: onQuery,
        ),
        const SizedBox(height: 12),
        // chips + sort
        Row(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill(text: 'All', selected: filterStars == 0, onTap: () => onFilterStars(0)),
                for (int s = 5; s >= 1; s--)
                  Pill(text: '$s★', selected: filterStars == s, onTap: () => onFilterStars(s)),
              ],
            ),
            const Spacer(),
            PopupMenuButton<SortBy>(
              tooltip: 'Sort',
              initialValue: sortBy,
              onSelected: onSortBy,
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: SortBy.newest, child: Text('Newest')),
                PopupMenuItem(value: SortBy.oldest, child: Text('Oldest')),
                PopupMenuItem(value: SortBy.helpful, child: Text('Most helpful')),
              ],
              child: Row(
                children: [
                  Icon(Icons.sort, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Text(
                    switch (sortBy) {
                      SortBy.newest => 'Newest',
                      SortBy.oldest => 'Oldest',
                      SortBy.helpful => 'Most helpful',
                    },
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// =======================================================
/// Add Review Card
/// =======================================================

class _AddReviewCard extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onStar;
  final String comment;
  final ValueChanged<String> onComment;
  final bool anonymous;
  final ValueChanged<bool> onAnon;
  final bool submitting;
  final VoidCallback onSubmit;

  const _AddReviewCard({
    required this.rating,
    required this.onStar,
    required this.comment,
    required this.onComment,
    required this.anonymous,
    required this.onAnon,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add your review',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Your rating:  '),
                StarRow(
                  filled: rating,
                  size: 28,
                  interactive: true,
                  onTap: onStar,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                hintText:
                    'Share details about safety, lighting, crowd, police presence...',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: onComment,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Switch(value: anonymous, onChanged: onAnon),
                const Text('Post anonymously'),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: const Text('Submit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// =======================================================
/// Review Tile
/// =======================================================

class _ReviewTile extends StatelessWidget {
  final Review review;
  final bool isMine;
  final VoidCallback onHelpful;
  final VoidCallback onReport;
  final VoidCallback? onDelete;

  const _ReviewTile({
    required this.review,
    required this.isMine,
    required this.onHelpful,
    required this.onReport,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = review.anonymous ? 'Anonymous' : review.displayName;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header row
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blueGrey.shade100,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          StarRow(filled: review.rating, size: 18),
                          const SizedBox(width: 8),
                          Text(_fmtDate(review.createdAt),
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                // actions
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Helpful',
                      onPressed: onHelpful,
                      icon: const Icon(Icons.thumb_up_alt_outlined),
                    ),
                    Text(review.helpfulCount.toString()),
                    const SizedBox(width: 6),
                    if (isMine && onDelete != null)
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                      )
                    else
                      IconButton(
                        tooltip: review.reported ? 'Reported' : 'Report',
                        onPressed: review.reported ? null : onReport,
                        icon: Icon(
                          review.reported ? Icons.flag : Icons.outlined_flag,
                          color: review.reported ? Colors.redAccent : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(review.comment),
          ],
        ),
      ),
    );
  }
}
