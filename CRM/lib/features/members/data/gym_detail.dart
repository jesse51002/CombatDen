/// The selected gym's full content detail, fetched once from the VideoService
/// (`GET /gyms/{gymId}`) and held in [SelectedGym] global memory. Mirrors the
/// service's `GymDetail` projection: the feed [spec] (descriptions), the
/// branded [classes], and the points-store [rewards]. The paginated video feed
/// is separate (see `VideoApiClient`).
///
/// Part of the read-only VideoService carve-out — these `fromJson`s track the
/// shape the service serves, the same way `Video.fromJson` does.
library;

/// The feed's surface/avoid descriptions: a short summary shown by default and
/// the full prompt revealed behind a "view full prompt" action.
class GymSpec {
  final String? shortVideosDesc;
  final String? shortAvoidDesc;
  final String videosDesc;
  final String avoidDesc;

  const GymSpec({
    required this.shortVideosDesc,
    required this.shortAvoidDesc,
    required this.videosDesc,
    required this.avoidDesc,
  });

  factory GymSpec.fromJson(Map<String, dynamic> json) => GymSpec(
    shortVideosDesc: json['short_videos_desc'] as String?,
    shortAvoidDesc: json['short_avoid_desc'] as String?,
    videosDesc: (json['videos_desc'] as String?) ?? '',
    avoidDesc: (json['avoid_desc'] as String?) ?? '',
  );

  /// The short summary when present, else the full prompt (short is optional
  /// until every gym is backfilled).
  String get surfaceSummary =>
      (shortVideosDesc?.isNotEmpty ?? false) ? shortVideosDesc! : videosDesc;
  String get avoidSummary =>
      (shortAvoidDesc?.isNotEmpty ?? false) ? shortAvoidDesc! : avoidDesc;
}

/// One points-store reward (the gym serves a network image url).
class Reward {
  final String title;
  final String imageUrl;

  /// Paid on top of points: "Free", "30% off". Capitalized at display time.
  final String priceLabel;
  final int pointsCost;

  const Reward({
    required this.title,
    required this.imageUrl,
    required this.priceLabel,
    required this.pointsCost,
  });

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
    title: (json['title'] as String?) ?? '',
    imageUrl: (json['image_url'] as String?) ?? '',
    priceLabel: (json['price_label'] as String?) ?? '',
    pointsCost: (json['points_cost'] as int?) ?? 0,
  );
}

/// One branded class card (the gym serves network image urls).
class GymClass {
  final String name;
  final String imageUrl;
  final String description;
  final String instructorName;
  final String instructorBio;
  final String instructorImageUrl;

  const GymClass({
    required this.name,
    required this.imageUrl,
    required this.description,
    required this.instructorName,
    required this.instructorBio,
    required this.instructorImageUrl,
  });

  factory GymClass.fromJson(Map<String, dynamic> json) => GymClass(
    name: (json['name'] as String?) ?? '',
    imageUrl: (json['image_url'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    instructorName: (json['instructor_name'] as String?) ?? '',
    instructorBio: (json['instructor_bio'] as String?) ?? '',
    instructorImageUrl: (json['instructor_image_url'] as String?) ?? '',
  );
}

/// The whole gym detail held in memory after selection.
class GymDetail {
  final String gymId;
  final String theme;
  final GymSpec spec;
  final List<GymClass> classes;
  final List<Reward> rewards;

  const GymDetail({
    required this.gymId,
    required this.theme,
    required this.spec,
    required this.classes,
    required this.rewards,
  });

  factory GymDetail.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) build) =>
        raw is List
        ? raw
              .whereType<Map>()
              .map((e) => build(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const [];
    final spec = json['specification'] ?? json['spec'];
    // The backend catalog uses `video_gym_id`; fall back to `gym_id` for any
    // legacy VideoService response during the transition period.
    final gymId =
        (json['video_gym_id'] as String?) ??
        (json['gym_id'] as String?) ??
        '';
    return GymDetail(
      gymId: gymId,
      theme: (json['theme'] as String?) ?? '',
      spec: GymSpec.fromJson(
        spec is Map ? Map<String, dynamic>.from(spec) : const {},
      ),
      classes: list(json['classes'], GymClass.fromJson),
      rewards: list(json['rewards'], Reward.fromJson),
    );
  }
}
