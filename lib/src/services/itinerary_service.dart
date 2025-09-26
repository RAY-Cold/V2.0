import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/itinerary/data/itinerary_dto.dart';

class UploadableFile {
  final String name;
  final String? path;     // mobile/desktop
  final Uint8List? bytes; // web
  const UploadableFile({required this.name, this.path, this.bytes});
}

class ItineraryService {
  final SupabaseClient _sb;
  static const _table = 'itineraries';
  static const _bucket = 'itinerary-attachments'; // create this bucket if you plan to upload

  ItineraryService(this._sb);

  Future<List<ItineraryDto>> listMine({int limit = 200}) async {
    final data = await _sb
        .from(_table)
        .select()
        .order('start_date', ascending: true)
        .limit(limit);

    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(ItineraryDto.fromMap)
        .toList();
  }

  Future<ItineraryDto> create({
    required String title,
    String? location,
    String? details,
    required DateTime startDate,
    required DateTime endDate,
    List<UploadableFile> files = const [],
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not signed in');

    final urls = await _uploadAll(uid: uid, files: files);

    final payload = <String, dynamic>{
      'user_id': uid,
      'title': title.trim(),
      'location': (location?.trim().isEmpty ?? true) ? null : location!.trim(),
      'details': (details?.trim().isEmpty ?? true) ? null : details!.trim(),
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
    };
    if (urls.isNotEmpty) payload['attachments'] = urls;

    final inserted = await _sb.from(_table).insert(payload).select().single();
    return ItineraryDto.fromMap(inserted);
  }

  Future<void> deleteById(String id) async {
    await _sb.from(_table).delete().eq('id', id);
  }

  Future<List<String>> _uploadAll({
    required String uid,
    required List<UploadableFile> files,
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
