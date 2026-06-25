/// Models for the presets domain.
///
/// [TemplateCard] mirrors `VideoTemplateCard` from the backend:
/// the slim picker card served by GET /api/v1/videos/templates.
///
/// [PresetImportResult] mirrors `PresetImportResponse`:
/// the result of POST /api/v1/gyms/{gym_id}/presets/import.
library;

/// One slim template card from the backend catalog.
/// Field names match the backend's `VideoTemplateCard` schema exactly.
class TemplateCard {
  final String videoGymId;
  final List<String> gymType;
  final String parentGymType;
  final String theme;
  final String celebrationImageUrl;
  final int videoCount;
  final bool hasClasses;
  final bool hasRewards;

  const TemplateCard({
    required this.videoGymId,
    required this.gymType,
    required this.parentGymType,
    required this.theme,
    required this.celebrationImageUrl,
    required this.videoCount,
    required this.hasClasses,
    required this.hasRewards,
  });

  factory TemplateCard.fromJson(Map<String, dynamic> json) => TemplateCard(
    videoGymId: (json['video_gym_id'] as String?) ?? '',
    gymType:
        (json['gym_type'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const [],
    parentGymType: (json['parent_gym_type'] as String?) ?? '',
    theme: (json['theme'] as String?) ?? '',
    celebrationImageUrl: (json['celebration_image_url'] as String?) ?? '',
    videoCount: (json['video_count'] as int?) ?? 0,
    hasClasses: (json['has_classes'] as bool?) ?? false,
    hasRewards: (json['has_rewards'] as bool?) ?? false,
  );

  /// Human-readable display name derived from the slug.
  String get displayName => videoGymId
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Result of a successful preset import.
/// Mirrors the backend's `PresetImportResponse` schema.
class PresetImportResult {
  final String gymId;
  final String videoGymId;
  final int videosImported;
  final int classesImported;
  final int rewardsImported;
  final String? themeDesignId;

  const PresetImportResult({
    required this.gymId,
    required this.videoGymId,
    required this.videosImported,
    required this.classesImported,
    required this.rewardsImported,
    required this.themeDesignId,
  });

  factory PresetImportResult.fromJson(Map<String, dynamic> json) =>
      PresetImportResult(
        gymId: (json['gym_id'] as String?) ?? '',
        videoGymId: (json['video_gym_id'] as String?) ?? '',
        videosImported: (json['videos_imported'] as int?) ?? 0,
        classesImported: (json['classes_imported'] as int?) ?? 0,
        rewardsImported: (json['rewards_imported'] as int?) ?? 0,
        themeDesignId: json['theme_design_id'] as String?,
      );
}
