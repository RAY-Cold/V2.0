import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/efir/data/efir_dto.dart';

/// Public helper so the UI can pass picked files here (web/mobile).
class EfirUploadable {
  final String name;
  final String? path;       // mobile/desktop
  final Uint8List? bytes;   // web
  const EfirUploadable({required this.name, this.path, this.bytes});
}

class EfirService {
  final SupabaseClient _sb;
  static const String _table = 'efir_reports';
  static const String _bucket = 'efir-attachments'; // make sure this bucket exists

  EfirService(this._sb);

  /// RLS already restricts to the logged-in user, so no filter is needed here.
  Future<List<EfirReportDto>> listMyReports({int limit = 200}) async {
    final data = await _sb
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(EfirReportDto.fromMap)
        .toList();
  }

  Future<EfirReportDto> create({
    required String name,
    required String description,
    String? contact,
    double? lat,
    double? lng,
    List<EfirUploadable> files = const [],
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not signed in');

    final urls = await _uploadAll(uid: uid, files: files);

    // NOTE: add `title: name` to satisfy legacy NOT NULL "title" if it still exists
    final payload = <String, dynamic>{
      'user_id': uid,
      'name': name,
      'title': name,
      'contact': (contact?.trim().isEmpty ?? true) ? null : contact!.trim(),
      'description': description.trim(),
      'lat': lat,
      'lng': lng,
    };
    if (urls.isNotEmpty) payload['attachments'] = urls;

    final inserted = await _sb.from(_table).insert(payload).select().single();
    return EfirReportDto.fromMap(inserted);
  }

  Future<List<String>> _uploadAll({
    required String uid,
    required List<EfirUploadable> files,
  }) async {
    if (files.isEmpty) return const [];
    final bucket = _sb.storage.from(_bucket);
    final urls = <String>[];

    for (final f in files) {
      final object = 'user_$uid/${DateTime.now().millisecondsSinceEpoch}_${f.name}';
      if (kIsWeb) {
        if (f.bytes == null) continue;
        await bucket.uploadBinary(object, f.bytes!, fileOptions: const FileOptions(upsert: false));
      } else {
        if (f.path == null) continue;
        await bucket.upload(object, File(f.path!));
      }
      urls.add(bucket.getPublicUrl(object)); // switch to signed URLs if bucket is private
    }
    return urls;
  }
}
