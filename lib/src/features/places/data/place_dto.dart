class PlaceDto {
  final String id;
  final String name;
  final String? address;
  PlaceDto({required this.id, required this.name, this.address});

  factory PlaceDto.fromMap(Map<String,dynamic> m) => PlaceDto(
    id: m['id'] as String,
    name: m['name'] as String,
    address: m['address'] as String?,
  );
}
