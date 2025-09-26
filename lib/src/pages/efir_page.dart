import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_page.dart';                 // 👈 import HomePage
import '../features/efir/data/efir_dto.dart';
import '../services/efir_service.dart';

class EFIRPage extends StatefulWidget {
  const EFIRPage({super.key});
  @override
  State<EFIRPage> createState() => _EFIRPageState();
}

class _EFIRPageState extends State<EFIRPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _desc = TextEditingController();

  late final EfirService _service;

  // location
  bool _usingLoc = false;
  double? _lat, _lng;

  // files (UI side)
  final List<_LocalPicked> _files = [];

  // list of my eFIRs (auto)
  List<EfirReportDto> _reports = [];
  bool _loadingList = false;
  bool _submitting = false;

  RealtimeChannel? _efirChannel;

  @override
  void initState() {
    super.initState();
    _service = EfirService(Supabase.instance.client);
    _loadReports();
    _listenRealtime(); // auto-refresh on inserts/updates
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _desc.dispose();
    _efirChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _loadingList = true);
    try {
      final res = await _service.listMyReports();
      if (mounted) setState(() => _reports = res);
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  void _listenRealtime() {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    _efirChannel = client
        .channel('public:efir_reports')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'efir_reports',
          callback: (payload) {
            if (payload.newRecord['user_id'] == uid) _loadReports();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'efir_reports',
          callback: (payload) {
            if (payload.newRecord['user_id'] == uid) _loadReports();
          },
        )
        .subscribe();
  }

  Future<void> _useMyLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Location services disabled');
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        throw Exception('Permission denied');
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _usingLoc = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location error: $e')));
    }
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: kIsWeb);
    if (res == null) return;
    setState(() {
      _files.addAll(res.files.map((pf) => _LocalPicked(
            name: pf.name,
            path: kIsWeb ? null : pf.path,
            bytes: kIsWeb ? pf.bytes : null, // Uint8List? on web
          )));
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final uploads = _files
          .map((f) => EfirUploadable(name: f.name, path: f.path, bytes: f.bytes))
          .toList();

      final created = await _service.create(
        name: _name.text.trim(),
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        description: _desc.text.trim(),
        lat: _usingLoc ? _lat : null,
        lng: _usingLoc ? _lng : null,
        files: uploads,
      );

      if (!mounted) return;
      final msg = created.referenceNo.isNotEmpty
          ? 'e-FIR submitted. Ref: ${created.referenceNo} (Pending)'
          : 'e-FIR submitted (Pending)';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

      _clearDraft();
      await _loadReports(); // realtime also refreshes
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _clearDraft() {
    _name.clear();
    _contact.clear();
    _desc.clear();
    _files.clear();
    _usingLoc = false;
    _lat = null;
    _lng = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    final formCard = Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                Expanded(child: Text('Submit Report', style: Theme.of(context).textTheme.titleMedium)),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _useMyLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use my location'),
                  ),
                  OutlinedButton(onPressed: _clearDraft, child: const Text('Clear Draft')),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _contact,
                  decoration: const InputDecoration(labelText: 'Contact (optional)'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              minLines: 5,
              maxLines: 10,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Describe the incident',
                hintText: 'Add place, time, people involved, identifiers…',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Description is required' : null,
            ),
            if (_usingLoc && _lat != null && _lng != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Attached location: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Choose Files'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _files.isEmpty ? 'no files selected' : _files.map((e) => e.name).join(', '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit'),
              ),
            ),
          ]),
        ),
      ),
    );

    final guidelinesCard = const Card(
      elevation: 1.5,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: _Guidelines(),
      ),
    );

    final headerRow = isWide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: formCard),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: guidelinesCard),
          ])
        : Column(children: [formCard, const SizedBox(height: 12), guidelinesCard]);

    // ---- SCROLL FIX + GO BACK BUTTON ----
    return Scaffold(
      appBar: AppBar(
        title: const Text('e-FIR'),
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
        onRefresh: _loadReports,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: headerRow,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Your e-FIRs', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            if (_loadingList)
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
              )
            else if (_reports.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No reports yet'),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _reportTile(_reports[i]),
                  ),
                  childCount: _reports.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _reportTile(EfirReportDto r) {
    Color statusColor(String s) {
      switch (s) {
        case 'Pending': return Colors.orange;
        case 'In Review': return Colors.blue;
        case 'Resolved': return Colors.green;
        case 'Rejected': return Colors.red;
        default: return Colors.grey;
      }
    }

    return Card(
      child: ListTile(
        title: Text(r.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.contact != null && r.contact!.isNotEmpty) Text('Contact: ${r.contact}'),
            Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (r.lat != null && r.lng != null)
              Text('Location: ${r.lat!.toStringAsFixed(5)}, ${r.lng!.toStringAsFixed(5)}'),
            Text('Filed: ${r.createdAt.toLocal()}'),
            if (r.attachments.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: r.attachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      r.attachments[i],
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor(r.status).withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(r.status, style: TextStyle(color: statusColor(r.status), fontWeight: FontWeight.w600)),
            ),
            if (r.referenceNo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(r.referenceNo, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Guidelines extends StatelessWidget {
  const _Guidelines();
  @override
  Widget build(BuildContext context) {
    Widget bullet(String s) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [const Text('•  '), Expanded(child: Text(s))],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Guidelines', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 10),
        bullet('Provide accurate contact details to enable follow-up.'),
        bullet('Use “Use my location” for precise coordinates.'),
        bullet('Keep your summary clear and under 1000 characters.'),
        bullet('Avoid posting passwords or personal IDs here.'),
      ],
    );
  }
}

class _LocalPicked {
  final String name;
  final String? path;
  final Uint8List? bytes;
  _LocalPicked({required this.name, this.path, this.bytes});
}
