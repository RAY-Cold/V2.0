class ItineraryDto {
  final String id;
  final String userId;
  final String title;
  final String? location;
  final String? details;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> attachments;
  final String referenceNo;
  final bool? done;
  final DateTime createdAt;
  final DateTime updatedAt;

  ItineraryDto({
    required this.id,
    required this.userId,
    required this.title,
    required this.location,
    required this.details,
    required this.startDate,
    required this.endDate,
    required this.attachments,
    required this.referenceNo,
    required this.createdAt,
    required this.updatedAt,
    this.done,
  });

  factory ItineraryDto.fromMap(Map<String, dynamic> m) {
    final atts = (m['attachments'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return ItineraryDto(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      title: (m['title'] ?? '') as String,
      location: m['location'] as String?,
      details: m['details'] as String?,
      startDate: DateTime.parse(m['start_date'].toString()),
      endDate: DateTime.parse(m['end_date'].toString()),
      attachments: atts,
      referenceNo: (m['reference_no'] ?? '') as String,
      done: m['done'] as bool?,
      createdAt: DateTime.parse(m['created_at'].toString()),
      updatedAt: DateTime.parse(m['updated_at'].toString()),
    );
  }
}
