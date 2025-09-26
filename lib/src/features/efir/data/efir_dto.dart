class EfirReportDto {
  final String id;
  final String userId;
  final String name;
  final String? contact;
  final String description;
  final double? lat;
  final double? lng;
  final List<String> attachments; // public or signed URLs
  final String status;            // 'Pending' | 'In Review' | 'Resolved' | 'Rejected'
  final String referenceNo;       // optional ('' if not used)
  final DateTime createdAt;

  EfirReportDto({
    required this.id,
    required this.userId,
    required this.name,
    required this.contact,
    required this.description,
    required this.lat,
    required this.lng,
    required this.attachments,
    required this.status,
    required this.referenceNo,
    required this.createdAt,
  });

  factory EfirReportDto.fromMap(Map<String, dynamic> m) {
    final atts = (m['attachments'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    return EfirReportDto(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      name: (m['name'] ?? '') as String,
      contact: m['contact'] as String?,
      description: (m['description'] ?? '') as String,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      attachments: atts,
      status: (m['status'] ?? 'Pending') as String,
      referenceNo: (m['reference_no'] ?? '') as String,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
