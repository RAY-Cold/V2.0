import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; // for image capture
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class DigitalIDPage extends StatefulWidget {
  const DigitalIDPage({super.key});

  @override
  State<DigitalIDPage> createState() => _DigitalIDPageState();
}

class _DigitalIDPageState extends State<DigitalIDPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _issuing = false;
  bool _active = false;

  BigInt? _passId;
  String? _qrJson;

  DateTime? _startDate;
  DateTime? _endDate;

  late String _apiBase; // e.g., http://10.0.2.2:5179 or http://<LAN-IP>:5179
  late String _userAddress; // owner of the pass

  final _client = http.Client();

  // For QR capture/export & QR animation
  final GlobalKey _qrRepaintKey = GlobalKey();
  late final AnimationController _animCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
        ..forward();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _client.close();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await dotenv.load(fileName: ".env");
    _apiBase = (dotenv.env['CHAIN_API'] ?? 'http://127.0.0.1:5179').trim();
    _userAddress =
        (dotenv.env['USER_ADDRESS'] ?? '0x0000000000000000000000000000000000000001')
            .trim();

    // ignore: avoid_print
    print('[DigitalID] CHAIN_API = $_apiBase');
    // ignore: avoid_print
    print('[DigitalID] USER_ADDRESS = $_userAddress');

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
      helpText: 'Select Start Date',
      builder: _datePickerBuilder,
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEnd() async {
    final base = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? base.add(const Duration(days: 1)),
      firstDate: base.add(const Duration(days: 1)),
      lastDate: base.add(const Duration(days: 180)),
      helpText: 'Select End Date',
      builder: _datePickerBuilder,
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Widget _datePickerBuilder(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        dialogBackgroundColor: Theme.of(context).colorScheme.surface,
        colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  String _fmt(DateTime? dt) =>
      dt == null ? '--/--/----' : DateFormat('yyyy-MM-dd').format(dt);

  Future<void> _testApi() async {
    try {
      final uri = Uri.parse('$_apiBase/health');
      final resp = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('API Health'),
          content: Text('Status: ${resp.statusCode}\nBody: ${resp.body}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      _showError('Health check timed out. Check CHAIN_API and firewall.');
    } catch (e) {
      if (!mounted) return;
      _showError('Health check failed: $e');
    }
  }

  Future<void> _issue() async {
    if (_startDate == null || _endDate == null) {
      _snack('Please choose start & end dates');
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      _snack('End date must be after start date');
      return;
    }

    setState(() => _issuing = true);
    try {
      final startUnix =
          DateTime(_startDate!.year, _startDate!.month, _startDate!.day)
                  .millisecondsSinceEpoch ~/
              1000;
      final endUnix =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59)
                  .millisecondsSinceEpoch ~/
              1000;

      final uri = Uri.parse('$_apiBase/issue-pass');
      final resp = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userAddress': _userAddress,
              'startAtSec': startUnix,
              'endAtSec': endUnix,
              'idHint': 'user-${DateTime.now().millisecondsSinceEpoch}',
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        throw Exception('API error ${resp.statusCode}: ${resp.body}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final passId = BigInt.parse(data['passId'] as String);
      final payloadForQr = data['payloadForQr'];

      setState(() {
        _passId = passId;
        _qrJson = jsonEncode(payloadForQr);
      });

      // Nice bounce-in when QR appears / updates
      _animCtrl.forward(from: 0);

      await _refreshActive();
    } on TimeoutException {
      _showError(
          'Issuing timed out. Verify CHAIN_API is reachable from device, and API/Hardhat are running.');
    } catch (e) {
      _showError('Issue failed: $e');
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _refreshActive() async {
    if (_passId == null) return;
    try {
      final uri = Uri.parse('$_apiBase/is-active/${_passId!}');
      final resp = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        throw Exception('API error ${resp.statusCode}: ${resp.body}');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _active = json['active'] as bool);
    } on TimeoutException {
      _showError('Status check timed out. Is the API reachable?');
    } catch (e) {
      _showError('Status check failed: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }

  Future<void> _copyQrJson() async {
    if (_qrJson == null) return;
    await Clipboard.setData(ClipboardData(text: _qrJson!));
    _snack('QR data copied');
  }

  // ────────────────────── NEW: PNG capture / save / share ──────────────────────
  Future<Uint8List?> _captureQrPng({double pixelRatio = 3.0}) async {
    try {
      final boundary = _qrRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      _showError('Could not capture QR: $e');
      return null;
    }
  }

  Future<File?> _writeTempPng(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/DigitalID_QR_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      _showError('Could not write file: $e');
      return null;
    }
  }

  Future<void> _saveQrPng() async {
    if (_qrJson == null) return;
    final bytes = await _captureQrPng();
    if (bytes == null) return;
    final file = await _writeTempPng(bytes);
    if (file == null) return;

    // On mobile, the temp path is fine; user can share/save. If you want gallery,
    // integrate image_gallery_saver (extra native setup).
    _snack('Saved to: ${file.path}');
  }

  Future<void> _shareQrPng() async {
    if (_qrJson == null) return;
    final bytes = await _captureQrPng();
    if (bytes == null) return;
    final file = await _writeTempPng(bytes);
    if (file == null) return;

    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'DigitalID_QR.png')],
        text:
            'My Digital ID QR (static). Valid: ${_fmt(_startDate)} → ${_fmt(_endDate)}',
      );
    } catch (e) {
      _showError('Share failed: $e');
    }
  }
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Digital ID')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Digital ID'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
        ),
        actions: [
          IconButton(
            tooltip: 'Test API',
            onPressed: _testApi,
            icon: const Icon(Icons.wifi_tethering),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Animated gradient backdrop
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOut,
              builder: (context, t, _) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(
                            scheme.primary.withOpacity(isDark ? 0.08 : 0.12),
                            scheme.secondary.withOpacity(isDark ? 0.06 : 0.1),
                            t)!,
                        scheme.surface,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                );
              },
            ),
          ),

          CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _HeaderCard(apiBase: _apiBase, userAddress: _userAddress),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Date selection + Generate button
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _DateAndActionCard(
                    start: _startDate,
                    end: _endDate,
                    onPickStart: _pickStart,
                    onPickEnd: _pickEnd,
                    issuing: _issuing,
                    onGenerate: _issue,
                    fmt: _fmt,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Status + QR card
              if (_passId != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _StatusAndQrCard(
                      active: _active,
                      onRefresh: _refreshActive,
                      hasQr: _active && _qrJson != null,
                      qrJson: _qrJson,
                      start: _startDate,
                      end: _endDate,
                      fmt: _fmt,
                      onCopy: _copyQrJson,
                      onSavePng: _saveQrPng,   // NEW
                      onSharePng: _shareQrPng, // NEW
                      qrRepaintKey: _qrRepaintKey,
                      animCtrl: _animCtrl,
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _EmptyStateCard(),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// UI SUBWIDGETS
// ───────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.apiBase, required this.userAddress});

  final String apiBase;
  final String userAddress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.surfaceVariant.withOpacity(0.6),
                scheme.surfaceVariant.withOpacity(0.3),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primary.withOpacity(0.12),
                child: Icon(Icons.verified_user, color: scheme.primary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Digital Identity',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'API: $apiBase',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'User: $userAddress',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: const Text('Secure'),
                avatar: const Icon(Icons.shield, size: 16),
                side: BorderSide(color: scheme.primary.withOpacity(0.35)),
                backgroundColor: scheme.primary.withOpacity(0.08),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateAndActionCard extends StatelessWidget {
  const _DateAndActionCard({
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
    required this.issuing,
    required this.onGenerate,
    required this.fmt,
  });

  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final bool issuing;
  final VoidCallback onGenerate;
  final String Function(DateTime?) fmt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Validity Window',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FieldTile(
                    label: 'Start Date',
                    value: fmt(start),
                    icon: Icons.event_available,
                    onTap: onPickStart,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldTile(
                    label: 'End Date',
                    value: fmt(end),
                    icon: Icons.event,
                    onTap: onPickEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: issuing ? null : onGenerate,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: issuing
                    ? SizedBox(
                        key: const ValueKey('sp'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.qr_code_2, key: ValueKey('qr')),
              ),
              label: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  issuing ? 'Generating…' : 'Generate Digital ID',
                  key: ValueKey(issuing),
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Note: Your QR encodes a static payload and will not change when refreshing the page.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusAndQrCard extends StatelessWidget {
  const _StatusAndQrCard({
    required this.active,
    required this.onRefresh,
    required this.hasQr,
    required this.qrJson,
    required this.start,
    required this.end,
    required this.fmt,
    required this.onCopy,
    required this.onSavePng, // NEW
    required this.onSharePng, // NEW
    required this.qrRepaintKey,
    required this.animCtrl,
  });

  final bool active;
  final VoidCallback onRefresh;
  final bool hasQr;
  final String? qrJson;
  final DateTime? start;
  final DateTime? end;
  final String Function(DateTime?) fmt;
  final VoidCallback onCopy;
  final VoidCallback onSavePng; // NEW
  final VoidCallback onSharePng; // NEW
  final GlobalKey qrRepaintKey;
  final AnimationController animCtrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Status + Refresh
            Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _StatusPill(key: ValueKey(active), active: active),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),

            // QR or Empty message with transition
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: hasQr
                  ? Column(
                      key: const ValueKey('qr-block'),
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              colors: [
                                scheme.primaryContainer.withOpacity(0.35),
                                scheme.surfaceVariant.withOpacity(0.15),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: scheme.outline.withOpacity(0.2),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 16),
                          child: Center(
                            child: ScaleTransition(
                              scale: CurvedAnimation(
                                parent: animCtrl,
                                curve: Curves.easeOutBack,
                              ),
                              child: FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: animCtrl,
                                  curve: Curves.easeOut,
                                ),
                                child: RepaintBoundary(
                                  key: qrRepaintKey,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              Colors.black.withOpacity(0.05),
                                          blurRadius: 20,
                                          spreadRadius: 4,
                                          offset: const Offset(0, 10),
                                        )
                                      ],
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: QrImageView(
                                      data: qrJson!,
                                      size: 220,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Valid: ${fmt(start)} → ${fmt(end)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: onCopy,
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy QR Data'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: onSavePng, // NEW
                              icon: const Icon(Icons.download),
                              label: const Text('Save PNG'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: onSharePng, // NEW
                              icon: const Icon(Icons.share),
                              label: const Text('Share'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Static • Will not change on refresh',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: Theme.of(context).hintColor),
                        ),
                      ],
                    )
                  : const _QrUnavailable(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primary.withOpacity(0.12),
              child: Icon(icon, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.edit_calendar, size: 18),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active, super.key});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? Colors.green : Colors.red;
    final label = active ? 'ACTIVE' : 'NOT ACTIVE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? Icons.verified : Icons.block, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _QrUnavailable extends StatelessWidget {
  const _QrUnavailable();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('qr-missing'),
      children: [
        const SizedBox(height: 8),
        Icon(Icons.qr_code_2, size: 56, color: Theme.of(context).disabledColor),
        const SizedBox(height: 8),
        Text(
          'QR not available (outside validity window).',
          style: TextStyle(
            color: Theme.of(context).hintColor,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: scheme.primary.withOpacity(0.12),
              child: Icon(Icons.qr_code, color: scheme.primary, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Choose a start and end date, then tap "Generate Digital ID" to create your static QR.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
