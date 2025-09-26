import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../features/efir/data/efir_dto.dart';
import '../services/efir_service.dart';
import '../home/home_page.dart';

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

  bool _usingLoc = false;
  double? _lat, _lng;

  final List<_LocalPicked> _files = [];

  List<EfirReportDto> _reports = [];
  bool _loadingList = false;
  bool _submitting = false;

  RealtimeChannel? _efirChannel;

  @override
  void initState() {
    super.initState();
    _service = EfirService(Supabase.instance.client);
    _loadReports();
    _listenRealtime();
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
            bytes: kIsWeb ? pf.bytes : null,
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
      await _loadReports();
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
    final isWide = MediaQuery.of(context).size.width >= 980;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: kBgGradient),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('e-FIR'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
            },
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadReports,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _GlassCard(child: _form())),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _GlassCard(child: const _Guidelines())),
                  ],
                )
              else ...[
                _GlassCard(child: _form()),
                const SizedBox(height: 12),
                _GlassCard(child: const _Guidelines()),
              ],
              const SizedBox(height: 24),
              Text('Your e-FIRs', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              if (_loadingList)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_reports.isEmpty)
                _GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No reports yet', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                  ),
                )
              else
                ..._reports.map(_reportTile),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                child: Text('Submit Report',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  style: _pillStyle,
                  onPressed: _useMyLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use my location'),
                ),
                OutlinedButton(style: _pillStyle, onPressed: _clearDraft, child: const Text('Clear Draft')),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _glassField(
                controller: _name,
                label: 'Your name',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _glassField(
                controller: _contact,
                label: 'Contact (optional)',
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _glassField(
            controller: _desc,
            label: 'Describe the incident',
            hint: 'Add place, time, people involved, identifiers…',
            minLines: 5,
            maxLines: 10,
            maxLength: 1000,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Description is required' : null,
          ),
          if (_usingLoc && _lat != null && _lng != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Attached location: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          const SizedBox(height: 8),
          _fileRow(),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _fileRow() {
    return Container(
      decoration: _inputDecorationBox,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.attach_file),
            label: const Text('Choose Files'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _files.isEmpty ? 'no files selected' : _files.map((e) => e.name).join(', '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportTile(EfirReportDto r) {
    Color statusColor(String s) {
      switch (s) {
        case 'Pending':
          return Colors.orangeAccent;
        case 'In Review':
          return Colors.lightBlueAccent;
        case 'Resolved':
          return Colors.greenAccent;
        case 'Rejected':
          return Colors.redAccent;
        default:
          return Colors.grey;
      }
    }

    final chipColor = statusColor(r.status);
    return _GlassCard(
      child: ListTile(
        title: Text(r.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.contact != null && r.contact!.isNotEmpty)
              Text('Contact: ${r.contact}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(r.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
            if (r.lat != null && r.lng != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Location: ${r.lat!.toStringAsFixed(5)}, ${r.lng!.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.white70)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Filed: ${r.createdAt.toLocal()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            if (r.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: r.attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(r.attachments[i], width: 64, height: 64, fit: BoxFit.cover),
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
                color: chipColor.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: chipColor.withOpacity(0.5)),
              ),
              child: Text(r.status, style: TextStyle(color: chipColor, fontWeight: FontWeight.w700)),
            ),
            if (r.referenceNo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(r.referenceNo, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }

  // ---- UI helpers ----
  final ButtonStyle _pillStyle = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: BorderSide(color: Colors.white.withOpacity(0.25)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
  );

  BoxDecoration get _inputDecorationBox => BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      );

  Widget _glassField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    int minLines = 1,
    int? maxLines,
    int? maxLength,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: TextFormField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines ?? 1,
          maxLength: maxLength,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            counterStyle: const TextStyle(color: Colors.white70),
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(color: Colors.white),
            hintStyle: const TextStyle(color: Colors.white70),
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
}

class _Guidelines extends StatelessWidget {
  const _Guidelines();
  @override
  Widget build(BuildContext context) {
    Widget bullet(String s) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [const Text('•  ', style: TextStyle(color: Colors.white)), Expanded(child: Text(s, style: const TextStyle(color: Colors.white70)))],
        );
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Guidelines', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
          const SizedBox(height: 10),
          bullet('Provide accurate contact details to enable follow-up.'),
          bullet('Use “Use my location” for precise coordinates.'),
          bullet('Keep your summary clear and under 1000 characters.'),
          bullet('Avoid posting passwords or personal IDs here.'),
        ],
      ),
    );
  }
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

class _LocalPicked {
  final String name;
  final String? path;
  final Uint8List? bytes;
  _LocalPicked({required this.name, this.path, this.bytes});
}
