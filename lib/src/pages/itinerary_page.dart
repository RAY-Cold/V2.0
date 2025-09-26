/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_page.dart'; // back target
import '../features/itinerary/data/itinerary_dto.dart';
import '../services/itinerary_service.dart';

class ItineraryPage extends StatefulWidget {
  const ItineraryPage({super.key});
  @override
  State<ItineraryPage> createState() => _ItineraryPageState();
}

class _ItineraryPageState extends State<ItineraryPage> {
  // Add form
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date;

  // Filters
  final _q = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  bool _ascending = true;

  // Data
  late final ItineraryService _service;
  List<ItineraryDto> _all = [];
  List<ItineraryDto> _visible = [];
  bool _loading = false;
  bool _saving = false;
  RealtimeChannel? _chan;

  @override
  void initState() {
    super.initState();
    _service = ItineraryService(Supabase.instance.client);
    _refresh();
    _listenRealtime();
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _q.dispose();
    _chan?.unsubscribe();
    super.dispose();
  }

  // ------------------- DATA -------------------
  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final res = await _service.listMine(limit: 500);
      _all = res;
      _applyFilters();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _listenRealtime() {
    final c = Supabase.instance.client;
    final uid = c.auth.currentUser?.id;
    if (uid == null) return;

    _chan = c
        .channel('public:itineraries')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'itineraries',
          callback: (p) {
            if (p.newRecord['user_id'] == uid) _refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'itineraries',
          callback: (p) {
            if (p.newRecord['user_id'] == uid) _refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'itineraries',
          callback: (p) {
            if (p.oldRecord['user_id'] == uid) _refresh();
          },
        )
        .subscribe();
  }

  // ------------------- ADD FORM -------------------
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (_date != null && !_isBeforeDay(_date!, today)) ? _date! : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today, // 🚫 no past dates
      lastDate: DateTime(today.year + 5),
      selectableDayPredicate: (d) {
        final day = DateTime(d.year, d.month, d.day);
        return !_isBeforeDay(day, today); // disable past cells
      },
    );

    if (picked != null) setState(() => _date = picked);
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() => _date = DateTime(now.year, now.month, now.day));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Guard: chosen date must be today or future
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chosen = _date ?? today;
    final chosenDay = DateTime(chosen.year, chosen.month, chosen.day);
    if (_isBeforeDay(chosenDay, today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick today or a future date')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final d = chosenDay;
      final created = await _service.create(
        title: _title.text.trim(),
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        details: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        startDate: d,
        endDate: d, // single-day item
      );

      if (!mounted) return;
      final msg = created.referenceNo.isNotEmpty
          ? 'Added. Ref: ${created.referenceNo}'
          : 'Itinerary item added';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _clearForm();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearForm() {
    _title.clear();
    _location.clear();
    _notes.clear();
    _date = null;
    setState(() {});
  }

  // ------------------- FILTERS + EXPORT -------------------
  void _applyFilters() {
    final q = _q.text.trim().toLowerCase();

    bool matches(ItineraryDto t) {
      final hitQ = q.isEmpty
          ? true
          : (t.title.toLowerCase().contains(q) ||
              (t.location ?? '').toLowerCase().contains(q) ||
              (t.details ?? '').toLowerCase().contains(q) ||
              t.referenceNo.toLowerCase().contains(q));
      final hitFrom = _from == null || !t.startDate.isBefore(_from!);
      final hitTo = _to == null || !t.endDate.isAfter(_to!);
      return hitQ && hitFrom && hitTo;
    }

    _visible = _all.where(matches).toList()
      ..sort((a, b) => _ascending
          ? a.startDate.compareTo(b.startDate)
          : b.startDate.compareTo(a.startDate));

    setState(() {});
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _from != null && !_isBeforeDay(_from!, today) ? _from! : today,
      firstDate: today, // filter "from" also not in the past (optional)
      lastDate: DateTime(today.year + 5),
      selectableDayPredicate: (d) => !_isBeforeDay(DateTime(d.year, d.month, d.day), today),
    );
    if (picked != null) {
      setState(() => _from = picked);
      _applyFilters();
    }
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final base = _from != null && !_isBeforeDay(_from!, today) ? _from! : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: _to != null && !_isBeforeDay(_to!, base) ? _to! : base,
      firstDate: base, // "to" can't be before "from"
      lastDate: DateTime(base.year + 5),
      selectableDayPredicate: (d) => !_isBeforeDay(DateTime(d.year, d.month, d.day), base),
    );
    if (picked != null) {
      setState(() => _to = picked);
      _applyFilters();
    }
  }

  void _toggleSort() {
    setState(() => _ascending = !_ascending);
    _applyFilters();
  }

  void _exportCSV() {
    final rows = <List<String>>[
      ['Title', 'Date', 'Location', 'Notes', 'Reference'],
      ..._visible.map((t) => [
            t.title,
            _fmtDate(t.startDate),
            t.location ?? '',
            (t.details ?? '').replaceAll('\n', ' '),
            t.referenceNo,
          ]),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    _showExportDialog('CSV', csv);
  }

  void _exportICS() {
    final buf = StringBuffer();
    buf.writeln('BEGIN:VCALENDAR');
    buf.writeln('VERSION:2.0');
    buf.writeln('PRODID:-//TourSecure//Itinerary//EN');
    for (final t in _visible) {
      final dt = _fmtDateICS(t.startDate);
      buf.writeln('BEGIN:VEVENT');
      buf.writeln('UID:${t.id}@toursecure');
      buf.writeln('DTSTAMP:${_fmtDateTimeICS(DateTime.now().toUtc())}');
      buf.writeln('DTSTART;VALUE=DATE:$dt');
      buf.writeln('DTEND;VALUE=DATE:$dt');
      buf.writeln('SUMMARY:${_escapeICS(t.title)}');
      if ((t.location ?? '').isNotEmpty) buf.writeln('LOCATION:${_escapeICS(t.location!)}');
      if ((t.details ?? '').isNotEmpty) buf.writeln('DESCRIPTION:${_escapeICS(t.details!)}');
      buf.writeln('END:VEVENT');
    }
    buf.writeln('END:VCALENDAR');
    _showExportDialog('ICS', buf.toString());
  }

  void _showExportDialog(String kind, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Export $kind'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(child: SelectableText(content)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  // ------------------- UI -------------------
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 920;

    final addCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add Itinerary Item', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickDate,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_date == null ? 'Select date' : _fmtDate(_date!)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _setToday, child: const Text('Today')),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add'),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Tip: Past dates are disabled. Pick today or a future date.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ),
    );

    final filtersCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Filters & Export', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            onChanged: (_) => _applyFilters(),
            decoration: const InputDecoration(hintText: 'Search title, location, notes...'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickFrom,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_from == null ? 'From' : _fmtDate(_from!)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _pickTo,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_to == null ? 'To' : _fmtDate(_to!)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _toggleSort,
                icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
                label: const Text('Sort by date'),
              ),
              const Spacer(),
              OutlinedButton(onPressed: _exportCSV, child: const Text('Export CSV')),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _exportICS, child: const Text('Export ICS')),
        ]),
      ),
    );

    final headerRow = isWide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: addCard),
            const SizedBox(width: 16),
            Expanded(child: filtersCard),
          ])
        : Column(children: [addCard, const SizedBox(height: 12), filtersCard]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Itinerary'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          tooltip: 'Back to Home',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            }
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: headerRow)),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Your Itinerary', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            if (_loading)
              const SliverToBoxAdapter(
                child: Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              )
            else if (_visible.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(16), child: Text('No items yet')),
              )
            else
              ..._buildGroupedSlivers(_visible),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ------------------- RENDER HELPERS -------------------
  List<Widget> _buildGroupedSlivers(List<ItineraryDto> list) {
    // group by date (yyyy-mm-dd)
    final map = <String, List<ItineraryDto>>{};
    for (final t in list) {
      final key = '${t.startDate.year}-${_two(t.startDate.month)}-${_two(t.startDate.day)}';
      (map[key] ??= []).add(t);
    }

    final keys = map.keys.toList()
      ..sort((a, b) => _ascending ? a.compareTo(b) : b.compareTo(a));

    final out = <Widget>[];
    for (final k in keys) {
      out.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      );
      out.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _itemTile(map[k]![i]),
            ),
            childCount: map[k]!.length,
          ),
        ),
      );
    }
    return out;
  }

  Widget _itemTile(ItineraryDto t) {
    final time = TimeOfDay.fromDateTime(t.createdAt);
    final timeStr = '${_two(time.hour)}:${_two(time.minute)}';

    return Card(
      child: ListTile(
        title: Text(t.title.toUpperCase()),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((t.location ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black26),
                  ),
                  child: Text((t.location ?? '').toUpperCase(),
                      style: const TextStyle(fontSize: 11, letterSpacing: 0.5)),
                ),
              ),
            Text('${_fmtDate(t.startDate)} • $timeStr'),
            if ((t.details ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.details!, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        trailing: FilledButton.tonal(
          onPressed: () async {
            await Supabase.instance.client.from('itineraries').update({'done': true}).eq('id', t.id);
            if (mounted) _refresh();
          },
          child: const Text('Done'),
        ),
      ),
    );
  }

  // ------------------- UTIL -------------------
  bool _isBeforeDay(DateTime a, DateTime b) {
    final ad = DateTime(a.year, a.month, a.day);
    final bd = DateTime(b.year, b.month, b.day);
    return ad.isBefore(bd);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _two(int v) => v < 10 ? '0$v' : '$v';
  String _fmtDateICS(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';
  String _fmtDateTimeICS(DateTime d) =>
      '${d.year}${_two(d.month)}${_two(d.day)}T${_two(d.hour)}${_two(d.minute)}${_two(d.second)}Z';
  String _escapeICS(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll('\n', '\\n');
}

// Minimal CSV converter (no dependency)
class ListToCsvConverter {
  const ListToCsvConverter();
  String convert(List<List<String>> rows) {
    String esc(String s) {
      final needQuotes =
          s.contains(',') || s.contains('\n') || s.contains('"') || s.contains('\r');
      final v = s.replaceAll('"', '""');
      return needQuotes ? '"$v"' : v;
    }

    return rows.map((r) => r.map(esc).join(',')).join('\n');
  }
}
*/
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../features/itinerary/data/itinerary_dto.dart';
import '../services/itinerary_service.dart';
import '../home/home_page.dart';

class ItineraryPage extends StatefulWidget {
  const ItineraryPage({super.key});
  @override
  State<ItineraryPage> createState() => _ItineraryPageState();
}

class _ItineraryPageState extends State<ItineraryPage> {
  late final ItineraryService _service;

  List<ItineraryDto> _all = [];
  List<ItineraryDto> _visible = [];
  bool _loading = true;

  // Filters
  String _query = '';
  bool _showUpcomingOnly = true;
  bool _ascending = true;

  // Form
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _service = ItineraryService(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _service.listMine(limit: 200);
      setState(() {
        _all = items;
      });
      _applyFilters();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final now = DateTime.now();
    final q = _query.trim().toLowerCase();
    List<ItineraryDto> list = List.of(_all);

    list = list.where((t) {
      if (_showUpcomingOnly && t.endDate.isBefore(DateTime(now.year, now.month, now.day))) return false;
      if (q.isEmpty) return true;
      final hay = '${t.title} ${t.location ?? ''} ${t.details ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();

    list.sort((a, b) => _ascending ? a.startDate.compareTo(b.startDate) : b.startDate.compareTo(a.startDate));
    setState(() => _visible = list);
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final res = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day), // no past dates
      lastDate: DateTime(now.year + 5),
      initialDate: _start ?? DateTime(now.year, now.month, now.day),
    );
    if (res != null) setState(() => _start = res);
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final first = _start ?? DateTime(now.year, now.month, now.day);
    final res = await showDatePicker(
      context: context,
      firstDate: first, // not before start & not in the past
      lastDate: DateTime(now.year + 5),
      initialDate: _end ?? first,
    );
    if (res != null) setState(() => _end = res);
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      _snack('Add a title');
      return;
    }
    if (_start == null || _end == null) {
      _snack('Pick start and end date');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _service.create(
        title: _title.text.trim(),
        startDate: _start!,
        endDate: _end!,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        details: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      _title.clear();
      _location.clear();
      _notes.clear();
      _start = null;
      _end = null;
      await _load();
    } catch (e) {
      _snack(e.toString());
    } finally {
      setState(() => _submitting = false);
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: kBgGradient),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Itinerary'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage())),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Create
                _GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create a plan',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        _glassField(controller: _title, label: 'Title'),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _glassField(controller: _location, label: 'Location (optional)')),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dateField(
                              label: 'Start date',
                              value: _start == null ? 'Pick date' : _fmtDate(_start!),
                              onTap: _pickStart,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dateField(
                              label: 'End date',
                              value: _end == null ? 'Pick date' : _fmtDate(_end!),
                              onTap: _pickEnd,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _glassField(controller: _notes, label: 'Notes (optional)', minLines: 3, maxLines: 5),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Add'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Filters
                _GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _searchField(
                            onChanged: (v) {
                              setState(() => _query = v);
                              _applyFilters();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilterChip(
                          selected: _showUpcomingOnly,
                          onSelected: (v) {
                            setState(() => _showUpcomingOnly = v);
                            _applyFilters();
                          },
                          label: const Text('Upcoming only'),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _ascending,
                          onSelected: (v) {
                            setState(() => _ascending = v);
                            _applyFilters();
                          },
                          label: Text(_ascending ? 'Ascending' : 'Descending'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // List
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(),
                  )
                else if (_visible.isEmpty)
                  _GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text('No itineraries yet', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                  )
                else
                  ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: _visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final t = _visible[i];
                      return _GlassCard(
                        child: ListTile(
                          title: Text(t.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('${_fmtDate(t.startDate)} → ${_fmtDate(t.endDate)}',
                                  style: const TextStyle(color: Colors.white70)),
                              if (t.location != null && t.location!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(t.location!, style: const TextStyle(color: Colors.white70)),
                                ),
                              if (t.details != null && t.details!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(t.details!, style: const TextStyle(color: Colors.white)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _dateField({required String label, required String value, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: _box,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _glassField({
    required TextEditingController controller,
    required String label,
    int minLines = 1,
    int? maxLines,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines ?? 1,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField({required ValueChanged<String> onChanged}) {
    return TextField(
      style: const TextStyle(color: Colors.white),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search…',
        hintStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.search, color: Colors.white),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
        ),
      ),
    );
  }

  BoxDecoration get _box => BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}
