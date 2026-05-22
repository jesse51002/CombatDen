/// One branded class card as served by the VideoService
/// (`GET /apps/{appId}/classes` → `ClassImage`). Field names mirror the API
/// so the JSON parse stays mechanical.
///
/// See `../VideoService/schema/class_output.py` for the source contract. The
/// service always returns exactly four of these.
class ClassInfo {
  const ClassInfo({
    required this.name,
    required this.imageUrl,
    required this.description,
    required this.instructorName,
    required this.instructorBio,
    required this.instructorImageUrl,
  });

  final String name;
  final String imageUrl;
  final String description;
  final String instructorName;
  final String instructorBio;
  final String instructorImageUrl;

  factory ClassInfo.fromJson(Map<String, dynamic> json) {
    return ClassInfo(
      name: (json['name'] as String?) ?? '',
      imageUrl: (json['image_url'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      instructorName: (json['instructor_name'] as String?) ?? '',
      instructorBio: (json['instructor_bio'] as String?) ?? '',
      instructorImageUrl: (json['instructor_image_url'] as String?) ?? '',
    );
  }
}
